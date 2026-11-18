import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../app/strings.dart';
import '../export/exporters.dart';
import '../export/search.dart';
import '../platform/platform_bridge.dart';
import '../player/audio_player.dart';
import '../storage/job.dart';
import '../transcription/transcript.dart';
import 'common.dart';
import 'progress_screen.dart';

/// Texte d'une transcription : lecture, relecture, recherche et export.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.controller, required this.jobId});

  final AppController controller;
  final String jobId;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  AppController get c => widget.controller;
  late Job job;
  List<Segment> segments = <Segment>[];
  late bool showTimestamps;
  bool searching = false;
  final TextEditingController searchField = TextEditingController();
  List<SearchHit> hits = <SearchHit>[];
  int hitIndex = 0;
  final ScrollController scroll = ScrollController();
  AudioPlayerController? player;
  StreamSubscription<PlayerState>? playerSub;
  PlayerState playerState = const PlayerState();
  double speed = 1.0;
  bool playerReady = false;

  @override
  void initState() {
    super.initState();
    job = c.jobs.load(widget.jobId)!;
    segments = c.transcriptOf(widget.jobId);
    showTimestamps = c.settings.exportTimestamps;
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    if (!job.hasAudio) return;
    final p = AudioPlayerController();
    try {
      await p.load(c.jobs.audioPath(job.id));
    } on PlatformFailure {
      await p.dispose();
      return;
    }
    if (!mounted) {
      await p.dispose();
      return;
    }
    player = p;
    playerSub = p.states.listen((st) {
      if (mounted) setState(() => playerState = st);
    });
    setState(() => playerReady = true);
  }

  @override
  void dispose() {
    playerSub?.cancel();
    player?.dispose();
    searchField.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _save() => c.saveEditedTranscript(job.id, segments);

  Future<void> _edit(int index) async {
    final s = c.strings;
    final controller = TextEditingController(text: segments[index].text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.t('edit_segment')} · ${clockTime(segments[index].startMs)}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          keyboardType: TextInputType.multiline,
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(s.t('save'))),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;
    setState(() {
      segments = List<Segment>.of(segments)..[index] = segments[index].copyWith(text: result.trim());
    });
    _save();
    _runSearch();
  }

  void _runSearch() {
    final found = searchSegments(segments, searchField.text);
    setState(() {
      hits = found;
      hitIndex = 0;
    });
    if (found.isNotEmpty) _scrollToSegment(found.first.segmentIndex);
  }

  void _scrollToSegment(int index) {
    if (!scroll.hasClients) return;
    final target = (index * 88.0).clamp(0.0, scroll.position.maxScrollExtent);
    scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _nextHit(int delta) {
    if (hits.isEmpty) return;
    setState(() => hitIndex = (hitIndex + delta) % hits.length);
    if (hitIndex < 0) hitIndex += hits.length;
    _scrollToSegment(hits[hitIndex].segmentIndex);
  }

  Future<void> _rename() async {
    final s = c.strings;
    final controller = TextEditingController(text: job.title);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('rename')),
        content: TextField(controller: controller, autofocus: true),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(s.t('save'))),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.trim().isEmpty) return;
    c.renameJob(job, result);
    setState(() => job = c.jobs.load(job.id)!);
  }

  Future<void> _share(ExportFormat format) async {
    final s = c.strings;
    try {
      await c.exporter.share(segments, format,
          title: job.title,
          chooserTitle: s.t('share_title'),
          timestamps: showTimestamps);
    } on PlatformFailure {
      if (mounted) toast(context, s.t('err_share'));
    }
  }

  Future<void> _shareAudio() async {
    final s = c.strings;
    try {
      await c.exporter.shareAudio(c.jobs.audioPath(job.id),
          title: job.title, chooserTitle: s.t('share_audio'));
    } on PlatformFailure {
      if (mounted) toast(context, s.t('err_share'));
    } on FileSystemException {
      if (mounted) toast(context, s.t('audio_missing'));
    }
  }

  Future<void> _saveAudio() async {
    final s = c.strings;
    try {
      final saved = await c.exporter.saveAudioAs(c.jobs.audioPath(job.id), title: job.title);
      if (saved && mounted) toast(context, s.t('file_saved'));
    } on PlatformFailure {
      if (mounted) toast(context, s.t('file_save_failed'));
    }
  }

  Future<void> _onMenu(String value) async {
    final s = c.strings;
    switch (value) {
      case 'copy':
        await c.exporter.copyText(segments, timestamps: showTimestamps);
        if (mounted) toast(context, s.t('copied'));
      case 'txt':
        await _share(ExportFormat.txt);
      case 'srt':
        await _share(ExportFormat.srt);
      case 'share_audio':
        await _shareAudio();
      case 'save_audio':
        await _saveAudio();
      case 'timestamps':
        setState(() => showTimestamps = !showTimestamps);
      case 'rename':
        await _rename();
      case 'dictionary':
        final ok = await confirm(context, c,
            title: s.t('apply_dictionary'),
            message: s.t('apply_dictionary_msg'),
            action: s.t('apply'));
        if (ok) {
          c.reapplyReplacements(job.id);
          setState(() => segments = c.transcriptOf(job.id));
        }
      case 'delete_audio':
        final ok = await confirm(context, c,
            title: s.t('delete_audio'),
            message: s.t('delete_audio_msg'),
            action: s.t('delete'));
        if (ok) {
          await player?.dispose();
          player = null;
          c.deleteAudioOf(job.id);
          setState(() {
            job = c.jobs.load(job.id)!;
            playerReady = false;
          });
        }
      case 'delete':
        final ok = await confirm(context, c,
            title: s.t('delete_transcription'),
            message: s.t('delete_transcription_msg'),
            action: s.t('delete'));
        if (ok) {
          await player?.dispose();
          player = null;
          c.deleteJob(job.id);
          if (mounted) Navigator.of(context).pop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = c.strings;
    final current = playerReady ? segmentIndexAt(segments, playerState.positionMs) : -1;
    final hitSegments = hits.map((h) => h.segmentIndex).toSet();
    final unfinished = job.status == JobStatus.interrupted || job.status == JobStatus.failed;
    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                controller: searchField,
                autofocus: true,
                decoration: InputDecoration(hintText: s.t('search'), border: InputBorder.none),
                onChanged: (_) => _runSearch(),
              )
            : Text(job.title, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          if (searching && hits.isNotEmpty) ...<Widget>[
            Center(child: Text('${hitIndex + 1}/${hits.length}')),
            IconButton(
                tooltip: s.t('previous'),
                onPressed: () => _nextHit(-1),
                icon: const Icon(Icons.keyboard_arrow_up)),
            IconButton(
                tooltip: s.t('next'),
                onPressed: () => _nextHit(1),
                icon: const Icon(Icons.keyboard_arrow_down)),
          ],
          IconButton(
            tooltip: searching ? s.t('close') : s.t('search'),
            icon: Icon(searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              searching = !searching;
              if (!searching) {
                searchField.clear();
                hits = <SearchHit>[];
              }
            }),
          ),
          PopupMenuButton<String>(
            tooltip: s.t('menu'),
            onSelected: _onMenu,
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'copy', child: Text(s.t('copy'))),
              PopupMenuItem<String>(value: 'txt', child: Text(s.t('share_txt'))),
              PopupMenuItem<String>(value: 'srt', child: Text(s.t('share_srt'))),
              if (job.hasAudio) ...<PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'share_audio', child: Text(s.t('share_audio'))),
                PopupMenuItem<String>(value: 'save_audio', child: Text(s.t('save_audio_as'))),
              ],
              CheckedPopupMenuItem<String>(
                  value: 'timestamps', checked: showTimestamps, child: Text(s.t('with_timestamps'))),
              const PopupMenuDivider(),
              PopupMenuItem<String>(value: 'rename', child: Text(s.t('rename'))),
              PopupMenuItem<String>(value: 'dictionary', child: Text(s.t('apply_dictionary'))),
              if (job.hasAudio)
                PopupMenuItem<String>(value: 'delete_audio', child: Text(s.t('delete_audio'))),
              PopupMenuItem<String>(value: 'delete', child: Text(s.t('delete_transcription'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (unfinished)
            MaterialBanner(
              content: Text(job.status == JobStatus.failed ? s.t('banner_failed') : s.t('banner_interrupted')),
              actions: <Widget>[
                TextButton(
                  onPressed: () async {
                    final started = await c.resume(job);
                    if (!mounted) return;
                    if (started) {
                      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
                          builder: (_) => ProgressScreen(controller: c)));
                    } else {
                      toast(context, s.t('cannot_resume'));
                    }
                  },
                  child: Text(s.t('resume')),
                ),
              ],
            ),
          Expanded(
            child: segments.isEmpty
                ? Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(s.t('no_text'), textAlign: TextAlign.center)))
                : ListView.builder(
                    controller: scroll,
                    itemCount: segments.length,
                    itemBuilder: (context, i) {
                      final seg = segments[i];
                      final highlighted = i == current;
                      final isHit = hitSegments.contains(i);
                      return Material(
                        color: highlighted
                            ? Theme.of(context).colorScheme.primaryContainer
                            : isHit
                                ? Theme.of(context).colorScheme.tertiaryContainer
                                : Colors.transparent,
                        child: ListTile(
                          title: Text(seg.text),
                          subtitle: Text(clockTime(seg.startMs)),
                          onTap: playerReady ? () => player?.seek(seg.startMs) : null,
                          trailing: IconButton(
                            tooltip: s.t('edit_segment'),
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(i),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (playerReady) _playerBar(s),
        ],
      ),
    );
  }

  Widget _playerBar(Strings s) {
    final duration = playerState.durationMs <= 0 ? 1 : playerState.durationMs;
    final position = playerState.positionMs.clamp(0, duration);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        child: Row(
          children: <Widget>[
            IconButton(
              tooltip: playerState.playing ? s.t('pause') : s.t('play'),
              icon: Icon(playerState.playing ? Icons.pause_circle : Icons.play_circle, size: 36),
              onPressed: () => playerState.playing ? player?.pause() : player?.play(),
            ),
            Expanded(
              child: Semantics(
                label: s.t('position'),
                child: Slider(
                  value: position.toDouble(),
                  max: duration.toDouble(),
                  onChanged: (v) => player?.seek(v.round()),
                ),
              ),
            ),
            Text(clockTime(position)),
            PopupMenuButton<double>(
              tooltip: s.t('speed'),
              initialValue: speed,
              onSelected: (v) {
                setState(() => speed = v);
                player?.setSpeed(v);
              },
              itemBuilder: (_) => <PopupMenuEntry<double>>[
                for (final v in const <double>[0.75, 1.0, 1.25, 1.5, 2.0])
                  PopupMenuItem<double>(value: v, child: Text('×$v')),
              ],
              child: Padding(padding: const EdgeInsets.all(8), child: Text('×$speed')),
            ),
          ],
        ),
      ),
    );
  }
}
