// Tests de la couche native. Pas de bibliothèque de test : de simples vérifications.
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "andika_whisper.h"

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond)                                                              \
  do {                                                                           \
    g_checks++;                                                                  \
    if (!(cond)) {                                                               \
      g_failures++;                                                              \
      fprintf(stderr, "ECHEC %s:%d : %s\n", __FILE__, __LINE__, #cond);         \
    }                                                                            \
  } while (0)

static void write_file(const char* path, const std::string& data) {
  FILE* f = fopen(path, "wb");
  fwrite(data.data(), 1, data.size(), f);
  fclose(f);
}

static std::string sha1_of(const std::string& data) {
  const char* path = "andika_test_sha1.tmp";
  write_file(path, data);
  char hex[41] = {0};
  int rc = andika_sha1_file(path, hex);
  remove(path);
  return rc == 0 ? std::string(hex) : std::string("ERREUR");
}

static void test_sha1() {
  // Vecteurs de test officiels (FIPS 180).
  CHECK(sha1_of("") == "da39a3ee5e6b4b0d3255bfef95601890afd80709");
  CHECK(sha1_of("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d");
  CHECK(sha1_of("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
        "84983e441c3bd26ebaae4aa1f95129e5e54670f1");
  CHECK(sha1_of(std::string(1000000, 'a')) == "34aa973cd4c4daa4f61eeb2bdbad27316534016f");
  // Taille juste avant et juste après une limite de bloc de 64 octets.
  CHECK(sha1_of(std::string(55, 'a')) == "c1c8bbdc22796e28c0e15163d20899b65621d65a");
  CHECK(sha1_of(std::string(56, 'a')) == "c2db330f6083854c99d4b5bfb6e8f29f201be699");
  CHECK(sha1_of(std::string(64, 'a')) == "0098ba824b5c16427bd7a1122a5a442a25ec644d");
  // Fichier absent.
  char hex[41];
  CHECK(andika_sha1_file("/chemin/inexistant/andika", hex) == -1);
  CHECK(strlen(andika_last_error()) > 0);
}

static void test_check_model() {
  CHECK(andika_check_model(ANDIKA_TEST_MODEL) == 1);
  CHECK(andika_check_model(ANDIKA_TEST_WAV) == 0);  // c'est un fichier WAV
  CHECK(andika_check_model("/chemin/inexistant/andika") == 0);
  CHECK(andika_check_model(nullptr) == 0);
}

static void test_memoire() {
  void* p = andika_malloc(1024);
  CHECK(p != nullptr);
  andika_dealloc(p);
  CHECK(andika_malloc(0) == nullptr);
  CHECK(andika_malloc(-5) == nullptr);
  andika_dealloc(nullptr);
}

static void test_parametres_invalides() {
  CHECK(andika_init(nullptr) == nullptr);
  CHECK(andika_init("/chemin/inexistant/model.bin") == nullptr);
  CHECK(strlen(andika_last_error()) > 0);
  CHECK(andika_transcribe(nullptr, nullptr, 0, "fr", 2) == ANDIKA_ERR_GENERIC);
  andika_free(nullptr);
  andika_cancel(nullptr);
  andika_reset_cancel(nullptr);
  CHECK(std::string(andika_segment_text(nullptr, 0)).empty());
  CHECK(andika_segment_t0_ms(nullptr, 0) == -1);
  CHECK(std::string(andika_detected_language(nullptr)).empty());
  CHECK(strlen(andika_version()) > 0);
}

// Le modèle « for-tests » du dépôt whisper.cpp ne contient pas de vrais poids :
// on vérifie seulement que la couche se comporte proprement (pas de plantage).
static void test_modele_factice() {
  andika_ctx* ctx = andika_init(ANDIKA_TEST_MODEL);
  if (ctx == nullptr) {
    printf("Info : le modèle factice n'est pas chargeable (%s)\n", andika_last_error());
    CHECK(strlen(andika_last_error()) > 0);
    return;
  }
  printf("Info : le modèle factice est chargé\n");
  std::vector<int16_t> silence(16000 * 3, 0);

  // Annulation avant le lancement : retour immédiat, sans traitement.
  andika_cancel(ctx);
  CHECK(andika_transcribe(ctx, silence.data(), (int32_t)silence.size(), "fr", 2) == ANDIKA_ERR_CANCELLED);
  CHECK(andika_transcribe(ctx, silence.data(), (int32_t)silence.size(), "fr", 2) == ANDIKA_ERR_CANCELLED);
  andika_reset_cancel(ctx);

  int32_t n = andika_transcribe(ctx, silence.data(), (int32_t)silence.size(), "fr", 2);
  printf("Info : transcription du silence -> %d\n", n);
  CHECK(n >= 0 || n == ANDIKA_ERR_GENERIC);
  for (int32_t i = 0; i < n; i++) {
    CHECK(andika_segment_t0_ms(ctx, i) >= 0);
    CHECK(andika_segment_t1_ms(ctx, i) <= 3000);
  }
  // Un morceau très court est complété sans erreur.
  std::vector<int16_t> court(1600, 0);
  n = andika_transcribe(ctx, court.data(), (int32_t)court.size(), "auto", 2);
  CHECK(n >= 0 || n == ANDIKA_ERR_GENERIC);
  andika_free(ctx);
}

int main() {
  test_sha1();
  test_check_model();
  test_memoire();
  test_parametres_invalides();
  test_modele_factice();
  printf("%d vérifications, %d échec(s)\n", g_checks, g_failures);
  return g_failures == 0 ? 0 : 1;
}
