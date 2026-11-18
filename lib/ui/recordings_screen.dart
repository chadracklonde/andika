import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../export/exporters.dart';
import '../platform/platform_bridge.dart';
import '../player/audio_player.dart';
import '../recorder/recording.dart';
import 'common.dart';
import 'new_transcription_screen.dart';
import 'recorder_screen.dart';

/// Bibliothèque des enregistrements : écouter, renommer, transcrire, récupérer l'audio.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  AppController get c => widget.controller;
  AudioPlayerController? _player;
  StreamSubscription<PlayerState>? _sub;
  PlayerState _state = const PlayerState();
  String? _playingId;
  String? _openId;

  @override
  void initState() {
    super.initState();
    c.refreshRecordings();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(Recording rec) async {
    final s = c.strings;
    if (_playingId == rec.id && _player != null) {
      _state.playing ? await _player!.pause() : await _player!.play();
      return;
    }
    await _sub?.cancel();
    await _player?.dispose();
    final p = AudioPlayerController();
    try {
      await p.load(c.recordingStore.wavPath(rec.id));
      await p.play();
    } on PlatformFailure {
      await p.dispose();
      if (mounted) toast(context, s.t('audio_missing'));
      return;
    }
    if (!mounted) {
      await p.dispose();
      return;
    }
    _player = p;
    _sub = p.states.listen((st) {
      if (mounted) setState(() => _state = st);
    });
    setState(() {
      _playingId = rec.id;
      _state = const PlayerState();
    });
  }

  /// Écoute à partir d'un repère.
  Future<void> _playFrom(Recording rec, int ms) async {
    if (_playingId != rec.id || _player == null) await _togglePlay(rec);
    if (_playingId == rec.id) {
      await _player?.seek(ms);
      if (!_state.playing) await _player?.play();
    }
  }

  Future<void> _rename(Recording rec) async {
    final s = c.strings;
    final field = TextEditingController(text: rec.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('rename')),
        content: TextField(controller: field, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, field.text), child: Text(s.t('save'))),
        ],
      ),
    );
    field.dispose();
    if (result != null) c.renameRecording(rec, result);
  }

  Future<void> _delete(Recording rec) async {
    final s = c.strings;
    final ok = await confirm(context, c,
        title: s.t('rec_delete_title'), message: s.t('rec_delete_message'), action: s.t('delete'));
    if (!ok || !mounted) return;
    if (_playingId == rec.id) {
      await _sub?.cancel();
      await _player?.dispose();
      _player = null;
      _sub = null;
      _playingId = null;
    }
    c.deleteRecording(rec.id);
  }

  Future<void> _share(Recording rec) async {
    final s = c.strings;
    final path = c.recordingStore.wavPath(rec.id);
    if (!File(path).existsSync()) {
      toast(context, s.t('audio_missing'));
      return;
    }
    try {
      await c.exporter.shareAudio(path, title: rec.title, chooserTitle: s.t('share_audio'));
    } on PlatformFailure {
      if (mounted) toast(context, s.t('file_save_failed'));
    }
  }

  Future<void> _saveAs(Recording rec) async {
    final s = c.strings;
    final path = c.recordingStore.wavPath(rec.id);
    if (!File(path).existsSync()) {
      toast(context, s.t('audio_missing'));
      return;
    }
    try {
      final saved = await c.exporter.saveAudioAs(path, title: rec.title);
      if (saved && mounted) toast(context, s.t('file_saved'));
    } on PlatformFailure {
      if (mounted) toast(context, s.t('file_save_failed'));
    }
  }

  void _transcribe(Recording rec) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NewTranscriptionScreen(controller: c, recording: rec),
    ));
  }

  /// Déplie ou replie une ligne ; replier arrête la lecture de cette ligne.
  Future<void> _toggleOpen(Recording rec) async {
    if (_openId == rec.id) {
      if (_playingId == rec.id && _state.playing) await _player?.pause();
      if (mounted) setState(() => _openId = null);
    } else {
      setState(() => _openId = rec.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.strings;
        final list = c.recordings;
        final theme = Theme.of(context);
        final used = formatBytes(c.recordingStore.totalBytes(), mb: s.t('unit_mb'), gb: s.t('unit_gb'));
        return Scaffold(
          appBar: AppBar(backgroundColor: Colors.transparent, scrolledUnderElevation: 0),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: Tooltip(
            message: s.t('rec_open_recorder'),
            child: Material(
              shape: const CircleBorder(),
              elevation: 4,
              color: theme.colorScheme.surface,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RecorderScreen(controller: c, fromLibrary: true),
                )),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE8473F)),
                  ),
                ),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  s.t('recordings'),
                  style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    s.t('rec_space_used', {'size': used}),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              const Divider(height: 1),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(s.t('rec_empty'),
                      textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
                )
              else
                for (final rec in list) _tile(context, rec),
            ],
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, Recording rec) {
    final s = c.strings;
    final theme = Theme.of(context);
    final open = _openId == rec.id;
    final playing = _playingId == rec.id;
    final isPlaying = playing && _state.playing;
    final duration = _state.durationMs <= 0 ? 1 : _state.durationMs;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: <Widget>[
        InkWell(
          onTap: () => _toggleOpen(rec),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        rec.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(formatDate(rec.createdAt), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(formatDuration(rec.durationMs), style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              children: <Widget>[
                if (playing)
                  Slider(
                    value: _state.positionMs.clamp(0, duration).toDouble(),
                    max: duration.toDouble(),
                    onChanged: (v) => _player?.seek(v.round()),
                  ),
                Row(
                  children: <Widget>[
                    IconButton(
                      tooltip: isPlaying ? s.t('pause') : s.t('rec_play'),
                      iconSize: 44,
                      icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill),
                      onPressed: () => _togglePlay(rec),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: s.t('share_audio'),
                      icon: const Icon(Icons.ios_share),
                      onPressed: () => unawaited(_share(rec)),
                    ),
                    IconButton(
                      tooltip: s.t('save_audio_as'),
                      icon: const Icon(Icons.save_alt),
                      onPressed: () => unawaited(_saveAs(rec)),
                    ),
                    IconButton(
                      tooltip: s.t('rename'),
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => unawaited(_rename(rec)),
                    ),
                    IconButton(
                      tooltip: s.t('delete'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => unawaited(_delete(rec)),
                    ),
                  ],
                ),
                if (rec.markers.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 4),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(s.t('rec_markers'), style: theme.textTheme.labelLarge),
                          for (final m in rec.markers)
                            ActionChip(
                              avatar: const Icon(Icons.flag, size: 16, color: Color(0xFFF59E0B)),
                              label: Text(clockTime(m)),
                              onPressed: () => unawaited(_playFrom(rec, m)),
                            ),
                        ],
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                    child: FilledButton.tonalIcon(
                      onPressed: () => _transcribe(rec),
                      icon: const Icon(Icons.subtitles_outlined),
                      label: Text(s.t('rec_transcribe')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1, indent: 20),
      ],
    );
  }
}
