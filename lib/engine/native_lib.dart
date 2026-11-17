import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:typed_data';

/// Erreur remontée par la couche native.
class EngineException implements Exception {
  EngineException(this.message);
  final String message;

  @override
  String toString() => 'EngineException: $message';
}

typedef _VersionC = ffi.Pointer<ffi.Uint8> Function();
typedef _VersionD = ffi.Pointer<ffi.Uint8> Function();

typedef _CheckModelC = ffi.Int32 Function(ffi.Pointer<ffi.Uint8>);
typedef _CheckModelD = int Function(ffi.Pointer<ffi.Uint8>);

typedef _Sha1C = ffi.Int32 Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>);
typedef _Sha1D = int Function(ffi.Pointer<ffi.Uint8>, ffi.Pointer<ffi.Uint8>);

typedef _InitC = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>);
typedef _InitD = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Uint8>);

typedef _VoidCtxC = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _VoidCtxD = void Function(ffi.Pointer<ffi.Void>);

typedef _TranscribeC = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int16>, ffi.Int32, ffi.Pointer<ffi.Uint8>, ffi.Int32);
typedef _TranscribeD = int Function(
    ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Int16>, int, ffi.Pointer<ffi.Uint8>, int);

typedef _SegTimeC = ffi.Int64 Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SegTimeD = int Function(ffi.Pointer<ffi.Void>, int);

typedef _SegTextC = ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>, ffi.Int32);
typedef _SegTextD = ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>, int);

typedef _CtxStrC = ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>);
typedef _CtxStrD = ffi.Pointer<ffi.Uint8> Function(ffi.Pointer<ffi.Void>);

typedef _MallocC = ffi.Pointer<ffi.Uint8> Function(ffi.Int64);
typedef _MallocD = ffi.Pointer<ffi.Uint8> Function(int);

typedef _DeallocC = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _DeallocD = void Function(ffi.Pointer<ffi.Void>);

/// Accès brut aux fonctions de `andika_whisper` (voir `andika_whisper.h`).
///
/// Chaque isolate Dart crée sa propre instance ; la bibliothèque native, elle,
/// n'est chargée qu'une fois par processus.
class NativeLib {
  NativeLib._(ffi.DynamicLibrary lib)
      : _version = lib.lookupFunction<_VersionC, _VersionD>('andika_version'),
        _lastError = lib.lookupFunction<_VersionC, _VersionD>('andika_last_error'),
        _checkModel = lib.lookupFunction<_CheckModelC, _CheckModelD>('andika_check_model'),
        _sha1File = lib.lookupFunction<_Sha1C, _Sha1D>('andika_sha1_file'),
        _init = lib.lookupFunction<_InitC, _InitD>('andika_init'),
        _free = lib.lookupFunction<_VoidCtxC, _VoidCtxD>('andika_free'),
        _cancel = lib.lookupFunction<_VoidCtxC, _VoidCtxD>('andika_cancel'),
        _resetCancel = lib.lookupFunction<_VoidCtxC, _VoidCtxD>('andika_reset_cancel'),
        _transcribe = lib.lookupFunction<_TranscribeC, _TranscribeD>('andika_transcribe'),
        _segT0 = lib.lookupFunction<_SegTimeC, _SegTimeD>('andika_segment_t0_ms'),
        _segT1 = lib.lookupFunction<_SegTimeC, _SegTimeD>('andika_segment_t1_ms'),
        _segText = lib.lookupFunction<_SegTextC, _SegTextD>('andika_segment_text'),
        _detectedLanguage = lib.lookupFunction<_CtxStrC, _CtxStrD>('andika_detected_language'),
        _malloc = lib.lookupFunction<_MallocC, _MallocD>('andika_malloc'),
        _dealloc = lib.lookupFunction<_DeallocC, _DeallocD>('andika_dealloc');

  final _VersionD _version;
  final _VersionD _lastError;
  final _CheckModelD _checkModel;
  final _Sha1D _sha1File;
  final _InitD _init;
  final _VoidCtxD _free;
  final _VoidCtxD _cancel;
  final _VoidCtxD _resetCancel;
  final _TranscribeD _transcribe;
  final _SegTimeD _segT0;
  final _SegTimeD _segT1;
  final _SegTextD _segText;
  final _CtxStrD _detectedLanguage;
  final _MallocD _malloc;
  final _DeallocD _dealloc;

  /// Charge la bibliothèque. Sur Android : `libandika_whisper.so`.
  /// Sur l'ordinateur (tests), le chemin peut être donné par la variable
  /// d'environnement ANDIKA_LIB.
  static NativeLib open() {
    final override = Platform.environment['ANDIKA_LIB'];
    final String name;
    if (override != null && override.isNotEmpty) {
      name = override;
    } else if (Platform.isAndroid || Platform.isLinux) {
      name = 'libandika_whisper.so';
    } else if (Platform.isWindows) {
      name = 'andika_whisper.dll';
    } else {
      name = 'libandika_whisper.dylib';
    }
    try {
      return NativeLib._(ffi.DynamicLibrary.open(name));
    } catch (e) {
      throw EngineException('Impossible de charger la bibliothèque native ($name) : $e');
    }
  }

  // --- Chaînes de caractères -------------------------------------------------

  /// Copie [text] (UTF-8, terminé par un octet nul) dans la mémoire native.
  /// L'appelant doit libérer avec [release].
  ffi.Pointer<ffi.Uint8> newCString(String text) {
    final bytes = utf8.encode(text);
    final ptr = _malloc(bytes.length + 1);
    if (ptr == ffi.nullptr) throw EngineException('Mémoire insuffisante');
    final view = ptr.asTypedList(bytes.length + 1);
    view.setAll(0, bytes);
    view[bytes.length] = 0;
    return ptr;
  }

  void release(ffi.Pointer<ffi.Void> ptr) => _dealloc(ptr);

  static String readCString(ffi.Pointer<ffi.Uint8> ptr) {
    if (ptr == ffi.nullptr) return '';
    var length = 0;
    while (ptr[length] != 0) {
      length++;
    }
    return utf8.decode(ptr.asTypedList(length), allowMalformed: true);
  }

  // --- Fonctions simples -----------------------------------------------------

  String get version => readCString(_version());

  String get lastError => readCString(_lastError());

  /// Vrai si le fichier commence comme un modèle ggml de whisper.cpp.
  bool checkModel(String path) {
    final p = newCString(path);
    try {
      return _checkModel(p) == 1;
    } finally {
      release(p.cast());
    }
  }

  /// SHA-1 d'un fichier, en hexadécimal minuscule. Bloquant : à appeler hors du
  /// fil principal pour les gros fichiers.
  String sha1File(String path) {
    final p = newCString(path);
    final out = _malloc(41);
    try {
      final rc = _sha1File(p, out);
      if (rc != 0) throw EngineException(lastError);
      return readCString(out);
    } finally {
      release(p.cast());
      release(out.cast());
    }
  }

  // --- Contexte Whisper ------------------------------------------------------

  ffi.Pointer<ffi.Void> init(String modelPath) {
    final p = newCString(modelPath);
    try {
      final ctx = _init(p);
      if (ctx == ffi.nullptr) throw EngineException(lastError);
      return ctx;
    } finally {
      release(p.cast());
    }
  }

  void free(ffi.Pointer<ffi.Void> ctx) => _free(ctx);

  void cancel(ffi.Pointer<ffi.Void> ctx) => _cancel(ctx);

  void resetCancel(ffi.Pointer<ffi.Void> ctx) => _resetCancel(ctx);

  /// Retourne le nombre de segments, -1 (erreur) ou -2 (annulé).
  int transcribe(ffi.Pointer<ffi.Void> ctx, Int16List pcm, String language, int threads) {
    final buffer = _malloc(pcm.length * 2).cast<ffi.Int16>();
    final lang = newCString(language);
    try {
      buffer.asTypedList(pcm.length).setAll(0, pcm);
      return _transcribe(ctx, buffer, pcm.length, lang, threads);
    } finally {
      release(buffer.cast());
      release(lang.cast());
    }
  }

  int segmentStartMs(ffi.Pointer<ffi.Void> ctx, int index) => _segT0(ctx, index);

  int segmentEndMs(ffi.Pointer<ffi.Void> ctx, int index) => _segT1(ctx, index);

  String segmentText(ffi.Pointer<ffi.Void> ctx, int index) => readCString(_segText(ctx, index));

  String detectedLanguage(ffi.Pointer<ffi.Void> ctx) => readCString(_detectedLanguage(ctx));
}
