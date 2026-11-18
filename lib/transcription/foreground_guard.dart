import 'dart:async';

import '../platform/platform_bridge.dart';
import 'transcription_runner.dart';

/// Textes de la notification (fournis par l'interface, donc traduits).
class ForegroundTexts {
  const ForegroundTexts({required this.title, required this.channelName, required this.progressText});

  final String title;
  final String channelName;

  /// Reçoit le pourcentage et retourne le texte (ex. « 42 % terminé »).
  final String Function(int percent) progressText;
}

/// Suit la progression d'une transcription et tient le service d'avant-plan à jour,
/// en n'actualisant la notification qu'à chaque changement de pourcentage.
Stream<RunProgress> withForeground(
  Stream<RunProgress> progress,
  PlatformBridge bridge,
  ForegroundTexts texts,
) async* {
  var lastPercent = -2;
  try {
    await for (final p in progress) {
      if (!p.isFinished) {
        final percent = p.fraction == null ? -1 : (p.fraction! * 100).floor();
        if (percent != lastPercent) {
          lastPercent = percent;
          try {
            await bridge.startForeground(
              title: texts.title,
              text: percent < 0 ? '' : texts.progressText(percent),
              progress: percent,
              channelName: texts.channelName,
            );
          } on PlatformFailure {
            // La notification est un confort : la transcription continue sans elle.
          }
        }
      }
      yield p;
    }
  } finally {
    try {
      await bridge.stopForeground();
    } catch (_) {}
  }
}
