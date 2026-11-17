#include "andika_whisper.h"

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "whisper.h"

namespace {

thread_local std::string g_last_error;

void set_error(const std::string& message) { g_last_error = message; }

// ----------------------------------------------------------------------------
// SHA-1 (implémentation compacte, validée par les tests natifs).
// ----------------------------------------------------------------------------
struct Sha1 {
  uint32_t h[5] = {0x67452301u, 0xEFCDAB89u, 0x98BADCFEu, 0x10325476u, 0xC3D2E1F0u};
  uint8_t buf[64];
  size_t buf_len = 0;
  uint64_t total = 0;

  static uint32_t rol(uint32_t v, int s) { return (v << s) | (v >> (32 - s)); }

  void block(const uint8_t* p) {
    uint32_t w[80];
    for (int i = 0; i < 16; i++) {
      w[i] = (uint32_t(p[i * 4]) << 24) | (uint32_t(p[i * 4 + 1]) << 16) |
             (uint32_t(p[i * 4 + 2]) << 8) | uint32_t(p[i * 4 + 3]);
    }
    for (int i = 16; i < 80; i++) w[i] = rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
    for (int i = 0; i < 80; i++) {
      uint32_t f, k;
      if (i < 20) {
        f = (b & c) | (~b & d);
        k = 0x5A827999u;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1u;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDCu;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6u;
      }
      uint32_t t = rol(a, 5) + f + e + k + w[i];
      e = d;
      d = c;
      c = rol(b, 30);
      b = a;
      a = t;
    }
    h[0] += a;
    h[1] += b;
    h[2] += c;
    h[3] += d;
    h[4] += e;
  }

  void update(const uint8_t* data, size_t len) {
    total += len;
    while (len > 0) {
      size_t take = 64 - buf_len;
      if (take > len) take = len;
      memcpy(buf + buf_len, data, take);
      buf_len += take;
      data += take;
      len -= take;
      if (buf_len == 64) {
        block(buf);
        buf_len = 0;
      }
    }
  }

  void finish(char* out_hex) {
    uint64_t bits = total * 8;
    uint8_t pad = 0x80;
    update(&pad, 1);
    uint8_t zero = 0;
    while (buf_len != 56) update(&zero, 1);
    uint8_t len_bytes[8];
    for (int i = 0; i < 8; i++) len_bytes[i] = uint8_t(bits >> (56 - 8 * i));
    update(len_bytes, 8);
    for (int i = 0; i < 5; i++) snprintf(out_hex + i * 8, 9, "%08x", h[i]);
  }
};

}  // namespace

struct andika_ctx {
  whisper_context* whisper = nullptr;
  std::atomic<bool> cancel{false};
  struct Segment {
    int64_t t0_ms;
    int64_t t1_ms;
    std::string text;
  };
  std::vector<Segment> segments;
  std::string detected_language;
};

namespace {

bool abort_callback(void* user_data) {
  auto* ctx = static_cast<andika_ctx*>(user_data);
  return ctx->cancel.load();
}

// Rend whisper.cpp silencieux (les messages ne servent à rien dans l'application).
void silent_log(enum ggml_log_level, const char*, void*) {}

}  // namespace

extern "C" {

ANDIKA_API const char* andika_version(void) { return "andika-whisper 1 (whisper.cpp 1.9.5)"; }

ANDIKA_API const char* andika_last_error(void) { return g_last_error.c_str(); }

ANDIKA_API int andika_check_model(const char* path) {
  if (path == nullptr) return 0;
  FILE* f = fopen(path, "rb");
  if (f == nullptr) {
    set_error(std::string("Fichier illisible : ") + path);
    return 0;
  }
  uint32_t magic = 0;
  size_t n = fread(&magic, 1, sizeof(magic), f);
  fclose(f);
  // Les modèles whisper (ggml) commencent par 0x67676d6c ("lmgg" en mémoire, petit-boutiste).
  return (n == sizeof(magic) && magic == 0x67676d6cu) ? 1 : 0;
}

ANDIKA_API int andika_sha1_file(const char* path, char* out_hex) {
  if (path == nullptr || out_hex == nullptr) return -1;
  FILE* f = fopen(path, "rb");
  if (f == nullptr) {
    set_error(std::string("Fichier illisible : ") + path);
    return -1;
  }
  Sha1 sha;
  std::vector<uint8_t> chunk(1 << 20);
  size_t n;
  while ((n = fread(chunk.data(), 1, chunk.size(), f)) > 0) sha.update(chunk.data(), n);
  bool ok = !ferror(f);
  fclose(f);
  if (!ok) {
    set_error("Erreur de lecture pendant le calcul de la somme de contrôle");
    return -1;
  }
  sha.finish(out_hex);
  return 0;
}

ANDIKA_API void* andika_malloc(int64_t size) {
  if (size <= 0) return nullptr;
  return malloc(static_cast<size_t>(size));
}

ANDIKA_API void andika_dealloc(void* ptr) { free(ptr); }

ANDIKA_API andika_ctx* andika_init(const char* model_path) {
  if (model_path == nullptr) {
    set_error("Chemin du modèle absent");
    return nullptr;
  }
  whisper_log_set(silent_log, nullptr);
  whisper_context_params cparams = whisper_context_default_params();
  cparams.use_gpu = false;
  whisper_context* w = whisper_init_from_file_with_params(model_path, cparams);
  if (w == nullptr) {
    set_error(std::string("Impossible de charger le modèle : ") + model_path);
    return nullptr;
  }
  auto* ctx = new andika_ctx();
  ctx->whisper = w;
  return ctx;
}

ANDIKA_API void andika_free(andika_ctx* ctx) {
  if (ctx == nullptr) return;
  if (ctx->whisper != nullptr) whisper_free(ctx->whisper);
  delete ctx;
}

ANDIKA_API void andika_cancel(andika_ctx* ctx) {
  if (ctx != nullptr) ctx->cancel.store(true);
}

ANDIKA_API void andika_reset_cancel(andika_ctx* ctx) {
  if (ctx != nullptr) ctx->cancel.store(false);
}

ANDIKA_API int32_t andika_transcribe(andika_ctx* ctx, const int16_t* pcm,
                                     int32_t n_samples, const char* language,
                                     int32_t n_threads) {
  if (ctx == nullptr || ctx->whisper == nullptr || pcm == nullptr || n_samples <= 0) {
    set_error("Paramètres invalides");
    return ANDIKA_ERR_GENERIC;
  }
  ctx->segments.clear();
  ctx->detected_language.clear();
  // L'indicateur d'annulation n'est jamais remis à zéro ici : une annulation reçue
  // entre deux morceaux ne doit pas être perdue (voir andika_reset_cancel).
  if (ctx->cancel.load()) return ANDIKA_ERR_CANCELLED;

  // Whisper veut au moins 1 seconde d'audio : on complète par du silence.
  const int32_t kMinSamples = 17600;  // 1,1 s à 16 kHz
  const int32_t n_real = n_samples;
  const int32_t n_total = n_samples < kMinSamples ? kMinSamples : n_samples;
  std::vector<float> samples(static_cast<size_t>(n_total), 0.0f);
  for (int32_t i = 0; i < n_real; i++) samples[static_cast<size_t>(i)] = pcm[i] / 32768.0f;

  whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.n_threads = n_threads > 0 ? n_threads : 2;
  params.translate = false;
  params.no_context = true;  // chaque morceau est indépendant (évite les boucles de répétition)
  params.print_progress = false;
  params.print_realtime = false;
  params.print_timestamps = false;
  params.print_special = false;
  params.suppress_nst = true;
  params.greedy.best_of = 1;
  const bool auto_lang = language == nullptr || language[0] == '\0' || strcmp(language, "auto") == 0;
  params.language = auto_lang ? "auto" : language;
  params.detect_language = false;  // "auto" suffit ; detect_language=true ne transcrirait pas
  params.abort_callback = abort_callback;
  params.abort_callback_user_data = ctx;

  int rc = whisper_full(ctx->whisper, params, samples.data(), n_total);
  if (ctx->cancel.load()) return ANDIKA_ERR_CANCELLED;
  if (rc != 0) {
    set_error("whisper_full a échoué (code " + std::to_string(rc) + ")");
    return ANDIKA_ERR_GENERIC;
  }

  const int64_t real_ms = static_cast<int64_t>(n_real) * 1000 / 16000;
  const int n = whisper_full_n_segments(ctx->whisper);
  for (int i = 0; i < n; i++) {
    andika_ctx::Segment seg;
    seg.t0_ms = whisper_full_get_segment_t0(ctx->whisper, i) * 10;  // unités de 10 ms
    seg.t1_ms = whisper_full_get_segment_t1(ctx->whisper, i) * 10;
    if (seg.t0_ms > real_ms) continue;  // segment dans le silence ajouté
    if (seg.t1_ms > real_ms) seg.t1_ms = real_ms;
    const char* text = whisper_full_get_segment_text(ctx->whisper, i);
    seg.text = text != nullptr ? text : "";
    ctx->segments.push_back(std::move(seg));
  }
  const int lang_id = whisper_full_lang_id(ctx->whisper);
  const char* lang = lang_id >= 0 ? whisper_lang_str(lang_id) : nullptr;
  ctx->detected_language = lang != nullptr ? lang : "";
  return static_cast<int32_t>(ctx->segments.size());
}

ANDIKA_API int64_t andika_segment_t0_ms(andika_ctx* ctx, int32_t index) {
  if (ctx == nullptr || index < 0 || static_cast<size_t>(index) >= ctx->segments.size()) return -1;
  return ctx->segments[static_cast<size_t>(index)].t0_ms;
}

ANDIKA_API int64_t andika_segment_t1_ms(andika_ctx* ctx, int32_t index) {
  if (ctx == nullptr || index < 0 || static_cast<size_t>(index) >= ctx->segments.size()) return -1;
  return ctx->segments[static_cast<size_t>(index)].t1_ms;
}

ANDIKA_API const char* andika_segment_text(andika_ctx* ctx, int32_t index) {
  if (ctx == nullptr || index < 0 || static_cast<size_t>(index) >= ctx->segments.size()) return "";
  return ctx->segments[static_cast<size_t>(index)].text.c_str();
}

ANDIKA_API const char* andika_detected_language(andika_ctx* ctx) {
  return ctx == nullptr ? "" : ctx->detected_language.c_str();
}

}  // extern "C"
