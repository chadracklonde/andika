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
import '../storage/job.dart';
import '../storage/job_store.dart';
import '../transcription/foreground_guard.dart';
import '../transcription/transcript.dart';
import '../transcription/transcription_runner.dart';
import 'settings.dart';
import 'strings.dart';

/// Transcription en cours, telle que l'interface l'affiche.
class ActiveTask {
  ActiveTask({required this.jobId, required this.title});

  final String jobId;
  final String title;

  /// `importing`, `transcribing`, `finishing`.
  String stage = 'importing';
  int importPercent = 0;
  RunProgress? progress;
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
  DeviceInfo? device;

  Settings settings = const Settings();
  List<Job> history = <Job>[];
  List<Replacement> replacements = <Replacement>[];
  ActiveTask? active;
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
    settings = _settingsStore.load();
    replacements = replacementStore.load();
    try {
      device = await _bridge.getDeviceInfo();
    } on PlatformFailure {
      device = null;
    }
    jobs.markInterrupted();
    refreshHistory();
    ready = true;
    notifyListeners();
  }

  /// Fichiers reçus pendant que l'application tourne.
  Stream<PickedFile> sharedFilesStream() => _bridge.sharedFiles;

  /// Fichier reçu au lancement (« Partager vers Andika »), une seule fois.
  Future<PickedFile?> initialShare() async {
    try {
      return await _bridge.getInitialShare();
    } on PlatformFailure {
      return null;
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
    try {
      await for (final p in stream) {
        last = p;
        task.progress = p;
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
      final segments = applyReplacementsToSegments(log.allSegments(), replacements);
      jobs.saveTranscript(job.id, segments);
      jobs.save(job.copyWith(status: JobStatus.done, detectedLanguage: detected));
      active = null;
    } else if (last != null && last.phase == RunPhase.cancelled) {
      jobs.save(job.copyWith(status: JobStatus.interrupted, detectedLanguage: detected));
      active = null;
    } else {
      jobs.save(job.copyWith(
          status: JobStatus.failed, detectedLanguage: detected, error: last?.error));
      task.errorKey = 'err_transcribe';
      task.errorDetail = last?.error;
    }
    refreshHistory();
  }

  /// Arrête la transcription en cours ; ce qui est fait reste enregistré.
  void cancelTranscription() {
    final task = active;
    if (task == null) return;
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
    jobs.saveTranscript(id, applyReplacementsToSegments(raw, replacements));
  }
}
