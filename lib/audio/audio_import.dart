import 'dart:async';

import '../platform/platform_bridge.dart';

/// Audio décodé et prêt à être transcrit.
class ImportedAudio {
  const ImportedAudio({required this.wavPath, required this.durationMs, required this.sampleCount});

  /// WAV 16 kHz mono conservé dans l'application (sert aussi à la lecture).
  final String wavPath;
  final int durationMs;
  final int sampleCount;
}

/// Espace libre minimal avant de décoder (le WAV pèse environ 2 Mo par minute).
const int kMinFreeStorageBytes = 300 * 1024 * 1024;

/// Dossier des fichiers audio d'une transcription, sous le dossier privé de l'application.
String audioPathFor(String filesDir, String jobId) => '$filesDir/audio/$jobId.wav';

/// Décode [file] (audio ou vidéo) en WAV 16 kHz mono.
///
/// [onProgress] reçoit un pourcentage entre 0 et 100. Lève [PlatformFailure]
/// (`no_space`, `no_audio`, `unsupported`, `read_error`, `decode_error`, `cancelled`).
Future<ImportedAudio> importAudio({
  required PickedFile file,
  required String jobId,
  void Function(int percent)? onProgress,
}) async {
  final bridge = PlatformBridge.instance;
  final paths = await bridge.getPaths();
  final info = await bridge.getDeviceInfo();
  if (info.freeStorageBytes < kMinFreeStorageBytes) {
    throw PlatformFailure('no_space', 'Espace de stockage insuffisant');
  }
  final outPath = audioPathFor(paths.files, jobId);
  final subscription = bridge.decodeProgress.listen((p) => onProgress?.call(p));
  try {
    final decoded = await bridge.decodeToWav(uri: file.uri, outPath: outPath);
    if (decoded.sampleCount <= 0) {
      throw PlatformFailure('no_audio', 'Aucun son détecté dans ce fichier');
    }
    return ImportedAudio(
      wavPath: outPath,
      durationMs: decoded.durationMs,
      sampleCount: decoded.sampleCount,
    );
  } finally {
    await subscription.cancel();
  }
}
