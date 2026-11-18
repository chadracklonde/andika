import 'dart:io';

import 'package:flutter/services.dart';

import '../platform/platform_bridge.dart';
import '../transcription/transcript.dart';
import 'exporters.dart';

/// Copie, enregistre et partage une transcription.
class ExportService {
  ExportService({required this.cacheDir, PlatformBridge? bridge})
      : _bridge = bridge ?? PlatformBridge.instance;

  /// Dossier cache de l'application (voir `getPaths`).
  final String cacheDir;
  final PlatformBridge _bridge;

  Future<void> copyText(List<Segment> segments, {bool timestamps = false}) {
    return Clipboard.setData(ClipboardData(text: toPlainText(segments, timestamps: timestamps)));
  }

  /// Écrit le fichier d'export dans cache/exports et retourne son chemin.
  File writeExport(
    List<Segment> segments,
    ExportFormat format, {
    required String title,
    bool timestamps = false,
    String subtitle = '',
  }) {
    final dir = Directory('$cacheDir/exports')..createSync(recursive: true);
    // Un seul export à la fois : on évite d'accumuler des fichiers.
    for (final e in dir.listSync()) {
      if (e is File) e.deleteSync();
    }
    final file = File('${dir.path}/${safeFileName(title)}.${exportExtension(format)}');
    file.writeAsBytesSync(
        exportBytes(segments, format, timestamps: timestamps, title: title, subtitle: subtitle),
        flush: true);
    return file;
  }

  Future<void> share(
    List<Segment> segments,
    ExportFormat format, {
    required String title,
    required String chooserTitle,
    bool timestamps = false,
    String subtitle = '',
  }) {
    final file =
        writeExport(segments, format, title: title, timestamps: timestamps, subtitle: subtitle);
    return _bridge.shareFile(path: file.path, mime: exportMime(format), title: chooserTitle);
  }

  /// « Enregistrer sous… » : l'utilisateur choisit le dossier et le nom. Faux s'il annule.
  Future<bool> saveAs(
    List<Segment> segments,
    ExportFormat format, {
    required String title,
    bool timestamps = false,
    String subtitle = '',
  }) {
    final file =
        writeExport(segments, format, title: title, timestamps: timestamps, subtitle: subtitle);
    return _bridge.saveFileAs(
      path: file.path,
      name: '${safeFileName(title)}.${exportExtension(format)}',
      mime: exportMime(format),
    );
  }

  /// Copie l'audio WAV dans cache/exports puis ouvre le menu de partage Android.
  Future<void> shareAudio(String wavPath, {required String title, required String chooserTitle}) async {
    final dir = Directory('$cacheDir/exports')..createSync(recursive: true);
    for (final e in dir.listSync()) {
      if (e is File) e.deleteSync();
    }
    final copy = await File(wavPath).copy('${dir.path}/${safeFileName(title)}.wav');
    await _bridge.shareFile(path: copy.path, mime: 'audio/wav', title: chooserTitle);
  }

  /// « Enregistrer sous… » : l'utilisateur choisit le dossier. Faux s'il annule.
  Future<bool> saveAudioAs(String wavPath, {required String title}) {
    return _bridge.saveFileAs(
        path: wavPath, name: '${safeFileName(title)}.wav', mime: 'audio/wav');
  }
}
