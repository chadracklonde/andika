import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/controller.dart';
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.strings;
        final list = c.recordings;
        final used = formatBytes(c.recordingStore.totalBytes(), mb: s.t('unit_mb'), gb: s.t('unit_gb'));
        return Scaffold(
          appBar: AppBar(title: Text(s.t('recordings'))),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => RecorderScreen(controller: c, fromLibrary: true),
            )),
            icon: const Icon(Icons.mic),
            label: Text(s.t('rec_open_recorder')),
          ),
          body: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(s.t('rec_empty'),
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(s.t('rec_space_used', {'size': used})),
                    ),
                    for (final rec in list) _tile(context, rec),
                  ],
                ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, Recording rec) {
    final s = c.strings;
    final playing = _playingId == rec.id;
    final isPlaying = playing && _state.playing;
    final duration = _state.durationMs <= 0 ? 1 : _state.durationMs;
    final size = formatBytes(rec.sizeBytes, mb: s.t('unit_mb'), gb: s.t('unit_gb'));
    return Column(
      children: <Widget>[
        ListTile(
          leading: IconButton(
            tooltip: isPlaying ? s.t('pause') : s.t('rec_play'),
            icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle, size: 36),
            onPressed: () => _togglePlay(rec),
          ),
          title: Text(rec.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${formatDate(rec.createdAt)} · ${formatDuration(rec.durationMs)} · $size'),
          trailing: PopupMenuButton<String>(
            tooltip: s.t('menu'),
            onSelected: (v) {
              switch (v) {
                case 'transcribe':
                  _transcribe(rec);
                case 'share':
                  unawaited(_share(rec));
                case 'save_as':
                  unawaited(_saveAs(rec));
                case 'rename':
                  unawaited(_rename(rec));
                case 'delete':
                  unawaited(_delete(rec));
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'transcribe', child: Text(s.t('rec_transcribe'))),
              PopupMenuItem<String>(value: 'share', child: Text(s.t('share_audio'))),
              PopupMenuItem<String>(value: 'save_as', child: Text(s.t('save_audio_as'))),
              const PopupMenuDivider(),
              PopupMenuItem<String>(value: 'rename', child: Text(s.t('rename'))),
              PopupMenuItem<String>(value: 'delete', child: Text(s.t('delete'))),
            ],
          ),
          onTap: () => _transcribe(rec),
        ),
        if (playing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Slider(
              value: _state.positionMs.clamp(0, duration).toDouble(),
              max: duration.toDouble(),
              onChanged: (v) => _player?.seek(v.round()),
            ),
          ),
      ],
    );
  }
}
