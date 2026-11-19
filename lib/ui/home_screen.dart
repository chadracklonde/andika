import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../export/exporters.dart';
import '../platform/platform_bridge.dart';
import '../recorder/recorder_controller.dart';
import '../storage/job.dart';
import 'about_screen.dart';
import 'common.dart';
import 'models_screen.dart';
import 'new_transcription_screen.dart';
import 'progress_screen.dart';
import 'recorder_screen.dart';
import 'recordings_screen.dart';
import 'result_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Accueil : historique et accès aux autres écrans.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    // Fichier reçu par « Partager vers Andika » pendant que l'application tourne.
    c.sharedFilesStream().listen(_openShared);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final first = await c.initialShares();
      if (mounted) _openShared(first);
    });
  }

  /// Un ou plusieurs fichiers reçus : le premier ouvre l'écran de réglages,
  /// les suivants sont traités à la suite avec les mêmes réglages.
  void _openShared(List<PickedFile> files) {
    if (!mounted || files.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NewTranscriptionScreen(
        controller: c,
        initialFile: files.first,
        extraFiles: files.sublist(1),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.strings;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Andika'),
            actions: <Widget>[
              IconButton(
                tooltip: s.t('search_all'),
                icon: const Icon(Icons.search),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SearchScreen(controller: c),
                )),
              ),
              IconButton(
                tooltip: s.t('recordings'),
                icon: const Icon(Icons.library_music_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RecordingsScreen(controller: c),
                )),
              ),
              PopupMenuButton<String>(
                tooltip: s.t('menu'),
                onSelected: (v) {
                  final Widget? page = switch (v) {
                    'models' => ModelsScreen(controller: c),
                    'settings' => SettingsScreen(controller: c),
                    'about' => AboutScreen(controller: c),
                    _ => null,
                  };
                  if (page != null) {
                    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
                  }
                },
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'models', child: Text(s.t('models'))),
                  PopupMenuItem<String>(value: 'settings', child: Text(s.t('settings'))),
                  PopupMenuItem<String>(value: 'about', child: Text(s.t('about'))),
                ],
              ),
            ],
          ),
          bottomNavigationBar: _ActionBar(controller: c),
          body: _body(context),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final s = c.strings;
    final children = <Widget>[];
    final task = c.active;
    if (c.recorder.active) {
      children.add(Card(
        child: ListenableBuilder(
          listenable: c.recorder,
          builder: (context, _) => ListTile(
            leading: const Icon(Icons.mic, color: Color(0xFFE8473F)),
            title: Text(s.t('rec_banner', {'time': clockTime(c.recorder.elapsedMs)})),
            subtitle: Text(c.recorder.state == RecState.paused ? s.t('rec_paused') : s.t('rec_recording')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => RecorderScreen(controller: c),
            )),
          ),
        ),
      ));
    }
    if (task != null) {
      children.add(Card(
        child: ListTile(
          leading: task.errorKey == null
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
              : const Icon(Icons.error_outline),
          title: Text(task.title),
          subtitle: Text(task.errorKey == null ? s.t('in_progress') : s.t(task.errorKey!)),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ProgressScreen(controller: c),
          )),
        ),
      ));
    }
    if (c.queue.isNotEmpty) {
      children.add(Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.queue),
              title: Text(s.t('queue_banner', {'n': '${c.queue.length}'})),
              subtitle: Text(c.queueHeld ? s.t('queue_held') : s.t('queue_waiting')),
            ),
            for (final item in c.queue)
              ListTile(
                dense: true,
                title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: s.t('queue_remove'),
                  icon: const Icon(Icons.close),
                  onPressed: () => c.removeFromQueue(item),
                ),
              ),
            OverflowBar(
              children: <Widget>[
                if (c.queueHeld && !c.busy)
                  TextButton(onPressed: c.resumeQueue, child: Text(s.t('queue_start'))),
                TextButton(onPressed: c.clearQueue, child: Text(s.t('queue_clear'))),
              ],
            ),
          ],
        ),
      ));
    }
    if (c.history.isEmpty && task == null && !c.recorder.active && c.queue.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(s.t('empty_history'), textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
        ),
      );
    }
    for (final job in c.history) {
      if (task != null && task.jobId == job.id) continue;
      children.add(_JobTile(controller: c, job: job));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: children);
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.controller, required this.job});

  final AppController controller;
  final Job job;

  @override
  Widget build(BuildContext context) {
    final s = controller.strings;
    final status = switch (job.status) {
      JobStatus.done => '',
      JobStatus.running => ' · ${s.t('in_progress')}',
      JobStatus.interrupted => ' · ${s.t('interrupted')}',
      JobStatus.failed => ' · ${s.t('failed')}',
    };
    return ListTile(
      leading: Icon(job.status == JobStatus.done ? Icons.description_outlined : Icons.pause_circle_outline),
      title: Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${formatDate(job.createdAt)} · ${formatDuration(job.durationMs)}$status'),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ResultScreen(controller: controller, jobId: job.id),
        ));
      },
    );
  }
}

/// Les deux actions principales, toujours visibles en bas : enregistrer (rouge) et
/// transcrire un fichier. Un appui sur « Enregistrer » démarre tout de suite.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.strings;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: ListenableBuilder(
                  listenable: c.recorder,
                  builder: (context, _) {
                    final active = c.recorder.active;
                    return FilledButton.icon(
                      key: const Key('record_button'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => RecorderScreen(controller: c, autoStart: !active),
                      )),
                      icon: Icon(active ? Icons.graphic_eq : Icons.mic, size: 28),
                      label: Text(
                        active
                            ? s.t('rec_button_active', {'time': clockTime(c.recorder.elapsedMs)})
                            : s.t('rec_button'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE8473F),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(60),
                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  key: const Key('transcribe_button'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => NewTranscriptionScreen(controller: c),
                  )),
                  icon: const Icon(Icons.upload_file, size: 26),
                  label: Text(s.t('transcribe_file'), maxLines: 2, textAlign: TextAlign.center),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(60),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
