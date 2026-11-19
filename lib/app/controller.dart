import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../audio/audio_import.dart';
import '../export/export_service.dart';
import '../extras/replacements.dart';
import '../models/model_catalog.dart';
import '../models/model_downloader.dart';
import '../models/model_store.dart';
import '../platform/platform_bridge.dart';
import '../recorder/recorder_controller.dart';
import '../recorder/recording.dart';
import '../recorder/recording_store.dart';
import '../storage/job.dart';
import '../storage/job_store.dart';
import '../transcription/cleanup.dart';
import '../transcription/eta.dart';
import '../transcription/foreground_guard.dart';
import '../transcription/transcript.dart';
import '../transcription/transcription_runner.dart';
import 'settings.dart';
import 'strings.dart';

/// Transcription en attente de son tour.
class QueuedItem {
  QueuedItem({
    required this.title,
    required this.language,
    required this.modelId,
    this.file,
    this.recording,
  });

  final String title;
  final String language;
  final String modelId;

  /// Fichier à importer, ou [recording] pour un enregistrement du dictaphone.
  final PickedFile? file;
  final Recording? recording;
}

/// Transcription en cours, telle que l'interface l'affiche.
class ActiveTask {
  ActiveTask({required this.jobId, required this.title});

  final String jobId;
  final String title;

  /// `importing`, `transcribing`, `finishing`.
  String stage = 'importing';
  int importPercent = 0;
  RunProgress? progress;

  /// Temps restant estimé, null tant que l'estimation n'est pas fiable.
  Duration? eta;
  String? errorKey;
  String? errorDetail;
}

/// État d'un téléchargement de modèle.
class ModelDownloadState {
  ModelDownloadState({this.fraction, this.verifying = false, this.errorKey});

  final double? fraction;
  final bool verifying;
  final String? errorKey;
}

/// Chef d'orchestre : réglages, historique, modèles et transcription en cours.
/// Une seule transcription à la fois (limite de mémoire et de batterie).
class AppController extends ChangeNotifier {
  AppController({PlatformBridge? bridge}) : _bridge = bridge ?? PlatformBridge.instance;

  final PlatformBridge _bridge;

  late String filesDir;
  late String cacheDir;
  late JobStore jobs;
  late ModelStore models;
  late SettingsStore _settingsStore;
  late ReplacementStore replacementStore;
  late ExportService exporter;
  late RecordingStore recordingStore;
  late RecorderController recorder;
  DeviceInfo? device;

  Settings settings = const Settings();
  List<Job> history = <Job>[];
  List<Recording> recordings = <Recording>[];
  List<Replacement> replacements = <Replacement>[];
  ActiveTask? active;

  /// File d'attente (en mémoire : perdue si l'application est fermée par le système).
  final List<QueuedItem> queue = <QueuedItem>[];

  /// Vrai quand la file est suspendue (pause, arrêt ou échec) : elle ne repart que sur demande.
  bool queueHeld = false;
  final Map<String, ModelDownloadState> downloads = <String, ModelDownloadState>{};
  final Map<String, DownloadCancelToken> _downloadTokens = <String, DownloadCancelToken>{};
  TranscriptionRunner? _runner;
  bool ready = false;

  Strings get strings => Strings.forSetting(settings.uiLanguage);

  Future<void> init() async {
    _bridge.start();
    final paths = await _bridge.getPaths();
    filesDir = paths.files;
    cacheDir = paths.cache;
    jobs = JobStore(filesDir);
    models = ModelStore(filesDir);
    _settingsStore = SettingsStore('$filesDir/settings.json');
    replacementStore = ReplacementStore('$filesDir/replacements.json');
    exporter = ExportService(cacheDir: cacheDir);
    recordingStore = RecordingStore(filesDir);
    recorder = RecorderController(
      store: recordingStore,
      texts: () {
        final s = strings;
        return RecorderTexts(
          title: s.t('rec_notif_title'),
          text: s.t('rec_notif_text'),
          channelName: s.t('rec_notif_channel'),
        );
      },
      defaultTitle: (utc) => strings.t('rec_default_title', {'date': formatShortDate(utc)}),
    );
    recorder.attach();
    recorder.addListener(_onRecorderChanged);
    settings = _settingsStore.load();
    replacements = replacementStore.load();
    try {
      device = await _bridge.getDeviceInfo();
    } on PlatformFailure {
      device = null;
    }
    jobs.markInterrupted();
    refreshHistory();
    await recorder.sync();
    refreshRecordings();
    ready = true;
    notifyListeners();
  }

  bool _recorderWasActive = false;
  RecState _lastRecState = RecState.idle;
  String? _lastRecError;

  /// Le dictaphone prévient à chaque tampon audio (plusieurs fois par seconde) : seuls
  /// les vrais changements (démarrage, pause, arrêt, erreur) sont relayés à l'application.
  /// Les écrans qui montrent le chronomètre ou le niveau écoutent `recorder` directement.
  void _onRecorderChanged() {
    final stopped = _recorderWasActive && !recorder.active;
    final changed = recorder.state != _lastRecState || recorder.errorKey != _lastRecError;
    _recorderWasActive = recorder.active;
    _lastRecState = recorder.state;
    _lastRecError = recorder.errorKey;
    // Une fiche vient d'être créée quand l'enregistreur repasse à l'arrêt.
    if (stopped) {
      refreshRecordings(); // prévient déjà les écouteurs
    } else if (changed) {
      notifyListeners();
    }
  }

  /// Relit la bibliothèque. À l'ouverture d'un écran (pendant sa construction), on passe
  /// `notify: false` : prévenir les écouteurs à ce moment-là est interdit par Flutter.
  void refreshRecordings({bool notify = true}) {
    recordings = recordingStore.list();
    if (notify) notifyListeners();
  }

  /// Fichiers reçus pendant que l'application tourne.
  Stream<List<PickedFile>> sharedFilesStream() => _bridge.sharedFiles;

  /// Fichiers reçus au lancement (« Partager vers Andika »), une seule fois.
  Future<List<PickedFile>> initialShares() async {
    try {
      return await _bridge.getInitialShares();
    } on PlatformFailure {
      return <PickedFile>[];
    }
  }

  Future<PickedFile?> pickAudio() async {
    try {
      return await _bridge.pickAudio();
    } on PlatformFailure {
      return null;
    }
  }

  void refreshHistory() {
    history = jobs.list();
    notifyListeners();
  }

  void updateSettings(Settings next) {
    settings = next;
    _settingsStore.save(next);
    notifyListeners();
  }

  void saveReplacements(List<Replacement> rules) {
    replacements = List<Replacement>.unmodifiable(rules);
    replacementStore.save(rules);
    notifyListeners();
  }

  int get totalRamBytes => device?.totalRamBytes ?? 0;

  bool get busy => active != null && active!.errorKey == null;

  // --- Modèles ---------------------------------------------------------------

  WhisperModel get selectedModel =>
      modelById(settings.modelId) ?? modelById(kRecommendedModelId)!;

  Future<void> downloadModel(WhisperModel model) async {
    if (downloads.containsKey(model.id) && downloads[model.id]!.errorKey == null) return;
    final token = DownloadCancelToken();
    _downloadTokens[model.id] = token;
    downloads[model.id] = ModelDownloadState(fraction: 0);
    notifyListeners();
    final downloader = ModelDownloader(store: models);
    try {
      await for (final p in downloader.download(
        model,
        freeStorageBytes: () async => (await _bridge.getDeviceInfo()).freeStorageBytes,
        cancelToken: token,
      )) {
        downloads[model.id] = ModelDownloadState(fraction: p.fraction, verifying: p.verifying);
        notifyListeners();
      }
      downloads.remove(model.id);
    } on ModelException catch (e) {
      if (e.code == 'cancelled') {
        downloads.remove(model.id);
      } else {
        final key = 'err_model_${e.code}';
        downloads[model.id] =
            ModelDownloadState(errorKey: strings.has(key) ? key : 'err_model_io');
      }
    } on PlatformFailure {
      downloads[model.id] = ModelDownloadState(errorKey: 'err_model_io');
    } finally {
      _downloadTokens.remove(model.id);
      notifyListeners();
    }
  }

  void cancelModelDownload(WhisperModel model) => _downloadTokens[model.id]?.cancel();

  void deleteModel(WhisperModel model) {
    models.delete(model);
    downloads.remove(model.id);
    notifyListeners();
  }

  // --- Transcription ---------------------------------------------------------

  static String titleFromFileName(String name) {
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final cleaned = base.replaceAll(RegExp(r'[_]+'), ' ').trim();
    return cleaned.isEmpty ? name : cleaned;
  }

  /// Importe un fichier puis lance la transcription. Retourne l'identifiant de la tâche,
  /// ou null si une autre tâche est déjà en cours ou si le modèle manque.
  Future<String?> startFromFile(PickedFile file, {String? language, WhisperModel? model}) async {
    if (busy) return null;
    final chosen = model ?? selectedModel;
    if (!models.isInstalled(chosen)) return null;
    final lang = language ?? settings.transcriptionLanguage;
    final id = jobs.newId();
    final task = ActiveTask(jobId: id, title: titleFromFileName(file.name));
    active = task;
    notifyListeners();
    try {
      final imported = await importAudio(
        file: file,
        jobId: id,
        onProgress: (p) {
          task.importPercent = p;
          notifyListeners();
        },
      );
      jobs.save(Job(
        id: id,
        title: task.title,
        createdAt: DateTime.now().toUtc(),
        durationMs: imported.durationMs,
        language: lang,
        modelId: chosen.id,
        status: JobStatus.running,
      ));
      refreshHistory();
      unawaited(_run(task, jobs.load(id)!));
      return id;
    } on PlatformFailure catch (e) {
      final key = 'err_import_${e.code}';
      task.errorKey = strings.has(key) ? key : 'err_import_unknown';
      task.errorDetail = e.message;
      notifyListeners();
      return null;
    }
  }

  /// Lance la transcription d'un enregistrement du dictaphone : son audio est copié
  /// dans l'espace de travail (l'enregistrement reste intact dans la bibliothèque).
  /// Retourne l'identifiant de la tâche, ou null si une autre tâche est en cours,
  /// si le modèle manque ou si l'audio est introuvable.
  Future<String?> startFromRecording(Recording rec, {String? language, WhisperModel? model}) async {
    if (busy) return null;
    final chosen = model ?? selectedModel;
    if (!models.isInstalled(chosen)) return null;
    final source = File(recordingStore.wavPath(rec.id));
    if (!source.existsSync()) return null;
    final lang = language ?? settings.transcriptionLanguage;
    final id = jobs.newId();
    final task = ActiveTask(jobId: id, title: rec.title)..stage = 'transcribing';
    active = task;
    notifyListeners();
    try {
      final free = (await _bridge.getDeviceInfo()).freeStorageBytes;
      if (free < source.lengthSync() + 50 * 1024 * 1024) {
        task.errorKey = 'err_import_no_space';
        notifyListeners();
        return null;
      }
      final target = File(jobs.audioPath(id));
      target.parent.createSync(recursive: true);
      await source.copy(target.path);
      jobs.save(Job(
        id: id,
        title: rec.title,
        createdAt: DateTime.now().toUtc(),
        durationMs: rec.durationMs,
        language: lang,
        modelId: chosen.id,
        status: JobStatus.running,
      ));
      refreshHistory();
      unawaited(_run(task, jobs.load(id)!));
      return id;
    } on PlatformFailure catch (e) {
      task.errorKey = 'err_import_unknown';
      task.errorDetail = e.message;
      notifyListeners();
      return null;
    } on FileSystemException catch (e) {
      task.errorKey = 'err_import_read_error';
      task.errorDetail = e.message;
      notifyListeners();
      return null;
    }
  }

  void renameRecording(Recording rec, String title) {
    recordingStore.rename(rec, title);
    refreshRecordings();
  }

  void deleteRecording(String id) {
    recordingStore.delete(id);
    refreshRecordings();
  }

  /// Reprend une transcription interrompue (les morceaux terminés sont conservés).
  Future<bool> resume(Job job) async {
    if (busy) return false;
    final model = modelById(job.modelId);
    if (model == null || !models.isInstalled(model)) return false;
    if (!File(jobs.audioPath(job.id)).existsSync()) return false;
    final task = ActiveTask(jobId: job.id, title: job.title)..stage = 'transcribing';
    active = task;
    jobs.save(job.copyWith(status: JobStatus.running));
    refreshHistory();
    unawaited(_run(task, jobs.load(job.id)!));
    return true;
  }

  Future<void> _run(ActiveTask task, Job job) async {
    task.stage = 'transcribing';
    notifyListeners();
    final model = modelById(job.modelId)!;
    final runner = TranscriptionRunner();
    _runner = runner;
    final s = strings;
    final stream = withForeground(
      runner.run(
        wavPath: jobs.audioPath(job.id),
        logPath: jobs.logPath(job.id),
        options: TranscriptionOptions(
          modelPath: models.pathFor(model),
          language: job.language,
          threads: defaultThreads(Platform.numberOfProcessors),
          skipSilence: settings.skipSilence,
        ),
      ),
      _bridge,
      ForegroundTexts(
        title: s.t('notif_title'),
        channelName: s.t('notif_channel'),
        progressText: (p) => s.t('notif_progress', {'n': '$p'}),
      ),
    );
    RunProgress? last;
    final estimator = EtaEstimator();
    try {
      await for (final p in stream) {
        last = p;
        task.progress = p;
        if (p.phase == RunPhase.transcribing && p.totalChunks > 0) {
          task.eta = estimator.update(p.doneChunks, p.totalChunks);
        }
        notifyListeners();
      }
    } finally {
      _runner = null;
    }
    _finish(task, job, last);
  }

  void _finish(ActiveTask task, Job job, RunProgress? last) {
    final log = jobs.log(job.id);
    final detected = log.dominantLanguage();
    if (last != null && last.phase == RunPhase.done) {
      final segments = applyReplacementsToSegments(cleanTranscript(log.allSegments()), replacements);
      jobs.saveTranscript(job.id, segments);
      jobs.save(job.copyWith(status: JobStatus.done, detectedLanguage: detected));
      active = null;
      refreshHistory();
      unawaited(_startNext());
      return;
    } else if (last != null && last.phase == RunPhase.cancelled) {
      jobs.save(job.copyWith(status: JobStatus.interrupted, detectedLanguage: detected));
      active = null;
    } else {
      jobs.save(job.copyWith(
          status: JobStatus.failed, detectedLanguage: detected, error: last?.error));
      task.errorKey = 'err_transcribe';
      task.errorDetail = last?.error;
      if (queue.isNotEmpty) queueHeld = true;
    }
    refreshHistory();
  }

  /// Met un fichier ou un enregistrement en file d'attente. Il démarre tout seul
  /// quand la transcription en cours se termine.
  void enqueue(QueuedItem item) {
    queue.add(item);
    notifyListeners();
  }

  void removeFromQueue(QueuedItem item) {
    queue.remove(item);
    if (queue.isEmpty) queueHeld = false;
    notifyListeners();
  }

  void clearQueue() {
    queue.clear();
    queueHeld = false;
    notifyListeners();
  }

  /// Relance la file après une pause, un arrêt ou un échec.
  void resumeQueue() {
    queueHeld = false;
    notifyListeners();
    unawaited(_startNext());
  }

  Future<void> _startNext() async {
    if (queue.isEmpty || queueHeld || busy) return;
    final item = queue.removeAt(0);
    notifyListeners();
    final model = modelById(item.modelId);
    String? id;
    if (model != null && models.isInstalled(model)) {
      id = item.recording != null
          ? await startFromRecording(item.recording!, language: item.language, model: model)
          : await startFromFile(item.file!, language: item.language, model: model);
    }
    if (id == null) {
      // Départ impossible (modèle supprimé, fichier disparu) : on suspend la file
      // plutôt que d'enchaîner en silence ; l'erreur éventuelle reste affichée.
      queueHeld = queue.isNotEmpty;
      notifyListeners();
    }
  }

  /// Arrête la transcription en cours ; ce qui est fait reste enregistré.
  /// La file d'attente est suspendue : elle repart sur demande (« Lancer »).
  void cancelTranscription() {
    final task = active;
    if (task == null) return;
    if (queue.isNotEmpty) queueHeld = true;
    if (task.stage == 'importing') {
      unawaited(_bridge.cancelDecode());
    } else {
      _runner?.cancel();
    }
  }

  /// Ferme le message d'erreur d'une tâche échouée.
  void dismissError() {
    if (active?.errorKey != null) {
      active = null;
      notifyListeners();
    }
  }

  // --- Résultat ---------------------------------------------------------------

  List<Segment> transcriptOf(String id) => jobs.loadTranscript(id);

  void saveEditedTranscript(String id, List<Segment> segments) {
    jobs.saveTranscript(id, segments);
  }

  void renameJob(Job job, String title) {
    final t = title.trim();
    if (t.isEmpty) return;
    jobs.save(job.copyWith(title: t));
    refreshHistory();
  }

  void deleteJob(String id) {
    jobs.delete(id);
    refreshHistory();
  }

  void deleteAudioOf(String id) {
    jobs.deleteAudio(id);
    refreshHistory();
  }

  /// Applique le dictionnaire au texte déjà transcrit d'une transcription.
  void reapplyReplacements(String id) {
    final raw = jobs.log(id).allSegments();
    jobs.saveTranscript(id, applyReplacementsToSegments(cleanTranscript(raw), replacements));
  }
}
