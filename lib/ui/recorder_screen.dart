import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../export/exporters.dart';
import '../recorder/recorder_controller.dart';
import '../recorder/recording.dart';
import 'common.dart';
import 'recordings_screen.dart';
import 'waveform.dart';

const Color _recRed = Color(0xFFE8473F);
const Color _doneBlue = Color(0xFF3B82F6);

/// Dictaphone : onde défilante, chronomètre, un grand bouton rouge, ✓ pour terminer.
class RecorderScreen extends StatefulWidget {
  const RecorderScreen({
    super.key,
    required this.controller,
    this.fromLibrary = false,
    this.autoStart = false,
  });

  final AppController controller;

  /// Démarre l'enregistrement dès l'ouverture (bouton « Enregistrer » de l'accueil).
  final bool autoStart;

  /// Ouvert depuis la bibliothèque : on y retourne après l'arrêt, sans la rouvrir.
  final bool fromLibrary;

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  AppController get c => widget.controller;
  bool get fromLibrary => widget.fromLibrary;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !c.recorder.active) c.recorder.start();
      });
    }
  }

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

  void _openLibrary(BuildContext context) {
    if (fromLibrary) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
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
        final theme = Theme.of(context);
        final subtitle = switch (r.state) {
          RecState.idle => s.t('rec_idle'),
          RecState.recording => clockTime(r.elapsedMs),
          RecState.paused => '${clockTime(r.elapsedMs)} · ${s.t('rec_paused')}',
        };
        final mainLabel = switch (r.state) {
          RecState.idle => s.t('rec_start'),
          RecState.recording => s.t('pause'),
          RecState.paused => s.t('resume'),
        };
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            scrolledUnderElevation: 0,
            actions: <Widget>[
              PopupMenuButton<String>(
                tooltip: s.t('menu'),
                icon: const _RoundIcon(icon: Icons.more_horiz),
                onSelected: (_) => _openLibrary(context),
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'library', child: Text(s.t('recordings'))),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12, left: 4),
                child: Opacity(
                  opacity: r.active ? 1 : 0.35,
                  child: Tooltip(
                    message: s.t('rec_stop'),
                    child: InkResponse(
                      onTap: r.active ? () => _stop(context) : null,
                      radius: 28,
                      child: const CircleAvatar(
                        radius: 22,
                        backgroundColor: _doneBlue,
                        child: Icon(Icons.check, color: Colors.white, size: 28),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 8),
                Text(
                  r.currentTitle ?? s.t('recorder'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 28),
                Semantics(
                  label: s.t('rec_level'),
                  child: RecordingWaveform(
                    levels: r.levels,
                    levelsOffset: r.levelsOffset,
                    elapsedMs: r.elapsedMs,
                    bucketMs: RecorderController.levelBucketMs,
                    markers: r.markers,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  formatPrecise(r.elapsedMs),
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
                  child: Text(
                    switch (r.state) {
                      RecState.idle => s.t('rec_hint_idle'),
                      RecState.recording => s.t('rec_hint_recording'),
                      RecState.paused => s.t('rec_hint_paused'),
                    },
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                if (r.errorKey != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Card(
                      color: theme.colorScheme.errorContainer,
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
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: <Widget>[
                      Tooltip(
                        message: s.t('recordings'),
                        child: InkResponse(
                          onTap: () => _openLibrary(context),
                          radius: 32,
                          child: const _RoundIcon(icon: Icons.format_list_bulleted, size: 52),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: mainLabel,
                          child: GestureDetector(
                            key: const Key('main_button'),
                            onTap: () {
                              switch (r.state) {
                                case RecState.idle:
                                  r.start();
                                case RecState.recording:
                                  r.pause();
                                case RecState.paused:
                                  r.resume();
                              }
                            },
                            child: Container(
                              height: 76,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(38),
                              ),
                              alignment: Alignment.center,
                              child: r.state == RecState.recording
                                  ? const _PauseGlyph()
                                  : const _RecordGlyph(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Tooltip(
                        message: s.t('rec_marker'),
                        child: InkResponse(
                          onTap: r.active
                              ? () {
                                  final at = r.addMarker();
                                  if (at != null) {
                                    toast(context, s.t('rec_marker_added', {'time': clockTime(at)}));
                                  }
                                }
                              : null,
                          radius: 32,
                          child: Opacity(
                            opacity: r.active ? 1 : 0.35,
                            child: const _RoundIcon(icon: Icons.flag_outlined, size: 52),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, this.size = 44});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Icon(icon, size: size * 0.5),
    );
  }
}

class _RecordGlyph extends StatelessWidget {
  const _RecordGlyph();

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: _recRed),
      );
}

class _PauseGlyph extends StatelessWidget {
  const _PauseGlyph();

  @override
  Widget build(BuildContext context) {
    Widget bar() => Container(
          width: 12,
          height: 38,
          decoration: BoxDecoration(color: _recRed, borderRadius: BorderRadius.circular(3)),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: <Widget>[bar(), const SizedBox(width: 10), bar()]);
  }
}
