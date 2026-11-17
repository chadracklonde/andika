import 'dart:async';
import 'dart:isolate';

import '../engine/whisper_engine.dart';
import 'transcript.dart';
import 'transcription_worker.dart';

enum RunPhase { loading, planning, transcribing, done, cancelled, failed }

/// État affiché pendant la transcription.
class RunProgress {
  const RunProgress({
    required this.phase,
    this.doneChunks = 0,
    this.totalChunks = 0,
    this.positionMs = 0,
    this.error,
  });

  final RunPhase phase;
  final int doneChunks;
  final int totalChunks;

  /// Fin du dernier morceau terminé, dans l'enregistrement.
  final int positionMs;
  final String? error;

  double? get fraction => totalChunks > 0 ? doneChunks / totalChunks : null;
  bool get isFinished =>
      phase == RunPhase.done || phase == RunPhase.cancelled || phase == RunPhase.failed;
}

/// Lance et suit une transcription dans un isolate. Une instance = une tâche.
class TranscriptionRunner {
  Isolate? _isolate;
  ReceivePort? _port;
  int? _engineAddress;
  bool _cancelRequested = false;

  /// Démarre la tâche. Le flux se termine avec un état final (fait, annulé, échec).
  Stream<RunProgress> run({
    required String wavPath,
    required String logPath,
    required TranscriptionOptions options,
  }) {
    final controller = StreamController<RunProgress>();
    final port = ReceivePort();
    final errors = ReceivePort();
    final exit = ReceivePort();
    _port = port;
    var finished = false;

    void finish(RunProgress last) {
      if (finished) return;
      finished = true;
      controller.add(last);
      port.close();
      errors.close();
      exit.close();
      _isolate = null;
      _engineAddress = null;
      controller.close();
    }

    var total = 0;
    var done = 0;
    var position = 0;
    controller.add(const RunProgress(phase: RunPhase.loading));

    port.listen((dynamic message) {
      final map = (message as Map).cast<String, Object?>();
      switch (map['type']) {
        case 'loaded':
          _engineAddress = map['address'] as int;
          // Une annulation demandée pendant le chargement est transmise dès que possible.
          if (_cancelRequested) WhisperEngine.cancelByAddress(_engineAddress!);
          controller.add(const RunProgress(phase: RunPhase.planning));
        case 'plan':
          total = map['total'] as int;
          done = map['done'] as int;
          controller.add(RunProgress(
              phase: RunPhase.transcribing, doneChunks: done, totalChunks: total));
        case 'chunk':
          done = map['done'] as int;
          total = map['total'] as int;
          position = map['positionMs'] as int;
          controller.add(RunProgress(
              phase: RunPhase.transcribing,
              doneChunks: done,
              totalChunks: total,
              positionMs: position));
        case 'done':
          finish(RunProgress(
              phase: RunPhase.done, doneChunks: total, totalChunks: total, positionMs: position));
        case 'cancelled':
          finish(RunProgress(
              phase: RunPhase.cancelled,
              doneChunks: done,
              totalChunks: total,
              positionMs: position));
        case 'error':
          finish(RunProgress(
              phase: RunPhase.failed,
              doneChunks: done,
              totalChunks: total,
              positionMs: position,
              error: map['message'] as String?));
      }
    });

    errors.listen((dynamic message) {
      final text = message is List && message.isNotEmpty ? '${message.first}' : '$message';
      finish(RunProgress(phase: RunPhase.failed, doneChunks: done, totalChunks: total, error: text));
    });
    // Fin de l'isolate sans message final (arrêt brutal) : on le signale.
    exit.listen((dynamic _) {
      finish(RunProgress(
          phase: _cancelRequested ? RunPhase.cancelled : RunPhase.failed,
          doneChunks: done,
          totalChunks: total,
          positionMs: position,
          error: _cancelRequested ? null : 'Le moteur s\'est arrêté de façon inattendue'));
    });

    Isolate.spawn<WorkerRequest>(
      transcriptionWorkerMain,
      WorkerRequest(
        wavPath: wavPath,
        logPath: logPath,
        options: options,
        events: port.sendPort,
      ),
      onError: errors.sendPort,
      onExit: exit.sendPort,
      errorsAreFatal: true,
    ).then((isolate) {
      _isolate = isolate;
      if (finished) isolate.kill(priority: Isolate.immediate);
    }, onError: (Object e) {
      finish(RunProgress(phase: RunPhase.failed, error: e.toString()));
    });

    controller.onCancel = () {
      if (!finished) cancel();
    };
    return controller.stream;
  }

  /// Demande l'arrêt. Le morceau en cours est interrompu côté natif ; les
  /// morceaux déjà terminés restent dans le journal, pour reprendre plus tard.
  void cancel() {
    _cancelRequested = true;
    final address = _engineAddress;
    if (address != null) WhisperEngine.cancelByAddress(address);
  }
}
