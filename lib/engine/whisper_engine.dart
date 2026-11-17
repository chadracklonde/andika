import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'native_lib.dart';

/// Un segment de texte, avec des temps en millisecondes relatifs au début
/// du morceau transcrit.
class RawSegment {
  const RawSegment({required this.startMs, required this.endMs, required this.text});

  final int startMs;
  final int endMs;
  final String text;
}

/// Résultat de la transcription d'un morceau.
class ChunkResult {
  const ChunkResult({required this.segments, required this.language, required this.cancelled});

  final List<RawSegment> segments;

  /// Langue détectée ou utilisée (code court), vide si inconnue.
  final String language;

  /// Vrai si la transcription a été interrompue par [WhisperEngine.cancel].
  final bool cancelled;
}

/// Moteur Whisper (un modèle chargé). À utiliser dans un seul isolate ;
/// seule [cancelByAddress] peut venir d'un autre isolate.
class WhisperEngine {
  WhisperEngine._(this._lib, this._ctx);

  final NativeLib _lib;
  ffi.Pointer<ffi.Void> _ctx;
  bool _disposed = false;

  /// Charge le modèle. Opération lente (plusieurs secondes pour un gros modèle).
  static WhisperEngine load(String modelPath) {
    final lib = NativeLib.open();
    if (!lib.checkModel(modelPath)) {
      throw EngineException('Ce fichier n\'est pas un modèle Whisper valide.');
    }
    return WhisperEngine._(lib, lib.init(modelPath));
  }

  /// Adresse du contexte natif. Elle peut être envoyée à un autre isolate
  /// pour appeler [cancelByAddress].
  int get address => _ctx.address;

  /// Demande l'arrêt depuis un autre isolate.
  static void cancelByAddress(int address) {
    final lib = NativeLib.open();
    lib.cancel(ffi.Pointer<ffi.Void>.fromAddress(address));
  }

  void cancel() => _lib.cancel(_ctx);

  /// À appeler au début d'une nouvelle tâche (voir andika_reset_cancel).
  void resetCancel() => _lib.resetCancel(_ctx);

  /// Transcrit un morceau de PCM 16 bits mono 16 kHz. Bloquant.
  ChunkResult transcribe(Int16List pcm, {String language = 'fr', int threads = 4}) {
    if (_disposed) throw EngineException('Le moteur a été libéré.');
    final n = _lib.transcribe(_ctx, pcm, language, threads);
    if (n == -2) {
      return const ChunkResult(segments: <RawSegment>[], language: '', cancelled: true);
    }
    if (n < 0) throw EngineException(_lib.lastError);
    final segments = <RawSegment>[];
    for (var i = 0; i < n; i++) {
      final text = _lib.segmentText(_ctx, i).trim();
      if (text.isEmpty) continue;
      segments.add(RawSegment(
        startMs: _lib.segmentStartMs(_ctx, i),
        endMs: _lib.segmentEndMs(_ctx, i),
        text: text,
      ));
    }
    return ChunkResult(
      segments: segments,
      language: _lib.detectedLanguage(_ctx),
      cancelled: false,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lib.free(_ctx);
    _ctx = ffi.nullptr;
  }
}
