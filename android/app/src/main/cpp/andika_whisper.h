// Couche C entre Flutter (dart:ffi) et whisper.cpp.
//
// Principes :
//  - aucune fonction de rappel (callback) vers Dart : on appelle andika_transcribe,
//    puis on relit les segments un par un ;
//  - un contexte (andika_ctx) = un modèle chargé ; il n'est pas partagé entre
//    plusieurs fils d'exécution, sauf andika_cancel qui peut être appelée depuis
//    un autre fil pendant une transcription.
#ifndef ANDIKA_WHISPER_H
#define ANDIKA_WHISPER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define ANDIKA_API __declspec(dllexport)
#else
#define ANDIKA_API __attribute__((visibility("default")))
#endif

typedef struct andika_ctx andika_ctx;

// Codes de retour de andika_transcribe (en plus du nombre de segments, >= 0).
#define ANDIKA_ERR_GENERIC   (-1)
#define ANDIKA_ERR_CANCELLED (-2)

// Version de la couche (texte statique).
ANDIKA_API const char* andika_version(void);

// Dernier message d'erreur (texte statique par fil d'exécution, jamais NULL).
ANDIKA_API const char* andika_last_error(void);

// Vérifie l'en-tête d'un fichier modèle. Retourne 1 si c'est un modèle ggml, 0 sinon.
ANDIKA_API int andika_check_model(const char* path);

// Calcule le SHA-1 d'un fichier (40 caractères hexadécimaux + octet nul dans out_hex,
// qui doit contenir au moins 41 octets). Retourne 0 si tout va bien, -1 sinon.
ANDIKA_API int andika_sha1_file(const char* path, char* out_hex);

// Allocation de mémoire native pour Dart (évite une dépendance à package:ffi).
// andika_malloc retourne NULL si la mémoire manque ; libérer avec andika_dealloc.
ANDIKA_API void* andika_malloc(int64_t size);
ANDIKA_API void andika_dealloc(void* ptr);

// Charge un modèle. Retourne NULL en cas d'échec (voir andika_last_error).
ANDIKA_API andika_ctx* andika_init(const char* model_path);

ANDIKA_API void andika_free(andika_ctx* ctx);

// Demande l'arrêt de la transcription en cours (peut être appelée depuis un autre fil).
ANDIKA_API void andika_cancel(andika_ctx* ctx);

// Remet à zéro l'indicateur d'annulation. À appeler au début d'une nouvelle tâche.
// Tant qu'il n'est pas remis à zéro, andika_transcribe retourne ANDIKA_ERR_CANCELLED.
ANDIKA_API void andika_reset_cancel(andika_ctx* ctx);

// Transcrit un morceau d'audio : PCM 16 bits, mono, 16 000 Hz.
//   language : code ("fr", "en", "sw"...) ou "auto" pour la détection.
// Retourne le nombre de segments (>= 0), ANDIKA_ERR_CANCELLED ou ANDIKA_ERR_GENERIC.
ANDIKA_API int32_t andika_transcribe(andika_ctx* ctx, const int16_t* pcm,
                                     int32_t n_samples, const char* language,
                                     int32_t n_threads);

// Lecture des segments du dernier appel. Les temps sont en millisecondes,
// relatifs au début du morceau. Le texte reste valide jusqu'au prochain appel.
ANDIKA_API int64_t andika_segment_t0_ms(andika_ctx* ctx, int32_t index);
ANDIKA_API int64_t andika_segment_t1_ms(andika_ctx* ctx, int32_t index);
ANDIKA_API const char* andika_segment_text(andika_ctx* ctx, int32_t index);

// Langue détectée lors du dernier appel (code à 2 ou 3 lettres, "" si inconnue).
ANDIKA_API const char* andika_detected_language(andika_ctx* ctx);

#ifdef __cplusplus
}
#endif

#endif  // ANDIKA_WHISPER_H
