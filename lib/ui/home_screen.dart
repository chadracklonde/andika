import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../export/exporters.dart';
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
    c.sharedFilesStream().listen((file) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => NewTranscriptionScreen(controller: c, initialFile: file),
      ));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final first = await c.initialShare();
      if (first != null && mounted) {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => NewTranscriptionScreen(controller: c, initialFile: first),
        ));
      }
    });
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
                tooltip: s.t('recorder'),
                icon: const Icon(Icons.mic_none),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => RecorderScreen(controller: c),
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
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => NewTranscriptionScreen(controller: c),
            )),
            icon: const Icon(Icons.add),
            label: Text(s.t('new_transcription')),
          ),
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
        child: ListTile(
          leading: const Icon(Icons.mic),
          title: Text(s.t('rec_banner', {'time': clockTime(c.recorder.elapsedMs)})),
          subtitle: Text(c.recorder.state == RecState.paused ? s.t('rec_paused') : s.t('rec_recording')),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => RecorderScreen(controller: c),
          )),
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
    if (c.history.isEmpty && task == null && !c.recorder.active) {
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
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: children);
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
