import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../export/exporters.dart';
import '../recorder/recorder_controller.dart';
import 'common.dart';
import 'recordings_screen.dart';

/// Dictaphone : enregistrer, mettre en pause, arrêter.
class RecorderScreen extends StatelessWidget {
  const RecorderScreen({super.key, required this.controller, this.fromLibrary = false});

  final AppController controller;

  /// Ouvert depuis la bibliothèque : on y retourne après l'arrêt, sans la rouvrir.
  final bool fromLibrary;

  AppController get c => controller;

  Future<void> _stop(BuildContext context) async {
    final navigator = Navigator.of(context);
    final saved = await c.recorder.stop();
    if (!context.mounted) return;
    if (saved == null) {
      // Vide ou perdu : le message d'erreur éventuel reste affiché.
      return;
    }
    c.refreshRecordings();
    toast(context, c.strings.t('rec_saved'));
    if (fromLibrary) {
      navigator.pop();
    } else {
      navigator.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => RecordingsScreen(controller: c),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c.recorder,
      builder: (context, _) {
        final s = c.strings;
        final r = c.recorder;
        final status = switch (r.state) {
          RecState.idle => s.t('rec_idle'),
          RecState.recording => s.t('rec_recording'),
          RecState.paused => s.t('rec_paused'),
        };
        return Scaffold(
          appBar: AppBar(
            title: Text(s.t('recorder')),
            actions: <Widget>[
              IconButton(
                tooltip: s.t('recordings'),
                icon: const Icon(Icons.library_music_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RecordingsScreen(controller: c),
                )),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Semantics(
                  liveRegion: true,
                  child: Text(status, style: Theme.of(context).textTheme.titleMedium),
                ),
                const SizedBox(height: 12),
                Text(
                  clockTime(r.elapsedMs),
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 24),
                Semantics(
                  label: s.t('rec_level'),
                  child: LinearProgressIndicator(
                    // Racine carrée : la voix normale reste bien visible.
                    value: math.sqrt(r.level),
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(height: 32),
                if (r.errorKey != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(s.t(r.errorKey!)),
                      trailing: IconButton(
                        tooltip: s.t('close'),
                        icon: const Icon(Icons.close),
                        onPressed: r.dismissError,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (!r.active)
                  FilledButton.icon(
                    onPressed: () => r.start(),
                    icon: const Icon(Icons.mic),
                    label: Text(s.t('rec_start')),
                    style: FilledButton.styleFrom(minimumSize: const Size(220, 64)),
                  )
                else ...<Widget>[
                  FilledButton.icon(
                    onPressed: () => _stop(context),
                    icon: const Icon(Icons.stop),
                    label: Text(s.t('rec_stop')),
                    style: FilledButton.styleFrom(minimumSize: const Size(220, 64)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: r.state == RecState.recording ? r.pause : r.resume,
                    icon: Icon(r.state == RecState.recording ? Icons.pause : Icons.play_arrow),
                    label: Text(r.state == RecState.recording ? s.t('pause') : s.t('resume')),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(220, 48)),
                  ),
                ],
                const SizedBox(height: 32),
                Text(s.t('rec_tip'), textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      },
    );
  }
}
