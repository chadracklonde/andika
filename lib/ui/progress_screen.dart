import 'package:flutter/material.dart';

import '../app/controller.dart';
import 'common.dart';
import 'result_screen.dart';

/// Suivi de la transcription en cours.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, required this.controller, this.openResultWhenDone = true});

  final AppController controller;
  final bool openResultWhenDone;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  AppController get c => widget.controller;
  String? _trackedJobId;
  bool _left = false;

  void _onChange() {
    if (!mounted || _left) return;
    final task = c.active;
    if (task == null && _trackedJobId != null) {
      // La tâche s'est terminée (ou a été arrêtée) : on quitte cet écran.
      _left = true;
      final id = _trackedJobId!;
      final nav = Navigator.of(context);
      if (widget.openResultWhenDone && c.jobs.load(id) != null) {
        nav.pushReplacement(MaterialPageRoute<void>(
          builder: (_) => ResultScreen(controller: c, jobId: id),
        ));
      } else {
        nav.pop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _trackedJobId = c.active?.jobId;
    c.addListener(_onChange);
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.strings;
        final task = c.active;
        if (task == null) {
          return Scaffold(
            appBar: AppBar(title: Text(s.t('progress'))),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final failed = task.errorKey != null;
        double? fraction;
        String label;
        if (failed) {
          label = s.t(task.errorKey!);
        } else if (task.stage == 'importing') {
          fraction = task.importPercent / 100;
          label = s.t('stage_importing', {'n': '${task.importPercent}'});
        } else {
          final p = task.progress;
          fraction = p?.fraction;
          if (p == null || p.totalChunks == 0) {
            label = s.t('stage_loading');
          } else {
            final percent = ((p.fraction ?? 0) * 100).floor();
            label = s.t('stage_transcribing', {'n': '$percent', 'pos': formatDuration(p.positionMs)});
          }
        }
        return Scaffold(
          appBar: AppBar(title: Text(task.title, overflow: TextOverflow.ellipsis)),
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (!failed)
                  Semantics(
                    label: label,
                    child: LinearProgressIndicator(value: fraction, minHeight: 10),
                  ),
                const SizedBox(height: 16),
                Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                if (failed && task.errorDetail != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(task.errorDetail!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 8),
                if (!failed) Text(s.t('keep_running_hint'), textAlign: TextAlign.center),
                const SizedBox(height: 32),
                if (failed)
                  FilledButton(
                    onPressed: () {
                      c.dismissError();
                    },
                    child: Text(s.t('close')),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await confirm(context, c,
                          title: s.t('stop_title'),
                          message: s.t('stop_message'),
                          action: s.t('stop'));
                      if (ok) c.cancelTranscription();
                    },
                    icon: const Icon(Icons.stop),
                    label: Text(s.t('stop')),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
