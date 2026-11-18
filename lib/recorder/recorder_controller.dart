import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../platform/platform_bridge.dart';
import 'recording.dart';
import 'recording_store.dart';

enum RecState { idle, recording, paused }

/// Textes de la notification de l'enregistreur.
class RecorderTexts {
  const RecorderTexts({required this.title, required this.text, required this.channelName});

  final String title;
  final String text;
  final String channelName;
}

/// Pilote le dictaphone : démarrage, pause, arrêt, niveau sonore, fiche finale.
class RecorderController extends ChangeNotifier {
  RecorderController({
    required this.store,
    required this.texts,
    required this.defaultTitle,
    PlatformBridge? bridge,
  }) : _bridge = bridge ?? PlatformBridge.instance;

  final RecordingStore store;
  final RecorderTexts Function() texts;

  /// Titre proposé à la création, selon la date (voir les textes de l'interface).
  final String Function(DateTime) defaultTitle;
  final PlatformBridge _bridge;

  RecState state = RecState.idle;
  int elapsedMs = 0;

  /// Niveau sonore de 0 à 1.
  double level = 0;

  /// Durée couverte par une valeur de [levels].
  static const int levelBucketMs = 100;
  static const int _maxLevels = 6000;

  /// Historique du niveau (le plus fort de chaque tranche de 100 ms), pour dessiner l'onde.
  /// L'indice 0 correspond à la tranche [levelsOffset].
  final List<double> levels = <double>[];
  int levelsOffset = 0;

  /// Titre que portera l'enregistrement en cours.
  String? currentTitle;

  /// Clé de texte de l'erreur à afficher, ou null.
  String? errorKey;

  String? _currentId;
  Recording? _lastFinished;
  StreamSubscription<Map<String, Object?>>? _sub;

  bool get active => state != RecState.idle;

  /// Dernier enregistrement terminé (utile si l'arrêt vient du système).
  Recording? get lastFinished => _lastFinished;

  void attach() {
    _sub ??= _bridge.events.listen(_onEvent);
  }

  /// Au démarrage : reprend l'état d'un enregistrement qui tourne encore (service resté
  /// en vie) ou retrouve ceux qu'un arrêt brutal a laissés sans fiche.
  Future<void> sync() async {
    Map<String, Object?> status;
    try {
      status = await _bridge.recorderStatus();
    } on PlatformFailure {
      status = <String, Object?>{'state': 'idle'};
    }
    final name = status['state'] as String? ?? 'idle';
    final path = status['path'] as String?;
    if (name != 'idle' && path != null) {
      _currentId = _idOf(path);
      state = name == 'paused' ? RecState.paused : RecState.recording;
      elapsedMs = (status['elapsedMs'] as num?)?.toInt() ?? 0;
    }
    store.recoverOrphans(titleFor: defaultTitle, skipPath: name != 'idle' ? path : null);
    notifyListeners();
  }

  static String _idOf(String path) {
    final name = path.split('/').last;
    return name.endsWith('.wav') ? name.substring(0, name.length - 4) : name;
  }

  /// Lance l'enregistrement. Retourne faux en cas d'échec ([errorKey] explique pourquoi).
  Future<bool> start() async {
    if (active) return false;
    errorKey = null;
    notifyListeners();
    try {
      if (!await _bridge.microphoneAllowed()) {
        if (!await _bridge.requestMicrophone()) {
          errorKey = 'err_rec_permission';
          notifyListeners();
          return false;
        }
      }
      try {
        // Sans cette autorisation (Android 13+), la notification du service est masquée.
        if (!await _bridge.notificationsAllowed()) await _bridge.requestNotifications();
      } on PlatformFailure {
        // Confort seulement : on enregistre quand même.
      }
      final id = store.newId();
      final t = texts();
      await _bridge.recorderStart(
        path: store.wavPath(id),
        title: t.title,
        text: t.text,
        channelName: t.channelName,
      );
      _currentId = id;
      _lastFinished = null;
      state = RecState.recording;
      elapsedMs = 0;
      level = 0;
      levels.clear();
      levelsOffset = 0;
      currentTitle = defaultTitle(DateTime.now().toUtc());
      notifyListeners();
      return true;
    } on PlatformFailure catch (e) {
      errorKey = _errorKeyFor(e.code);
      notifyListeners();
      return false;
    }
  }

  Future<void> pause() async {
    if (state != RecState.recording) return;
    try {
      await _bridge.recorderPause();
      state = RecState.paused;
      level = 0;
      notifyListeners();
    } on PlatformFailure {
      // sans effet
    }
  }

  Future<void> resume() async {
    if (state != RecState.paused) return;
    try {
      await _bridge.recorderResume();
      state = RecState.recording;
      notifyListeners();
    } on PlatformFailure {
      // sans effet
    }
  }

  /// Arrête et enregistre la fiche. Retourne l'enregistrement, ou null s'il est vide.
  Future<Recording?> stop() async {
    if (!active) return _lastFinished;
    try {
      await _bridge.recorderStop();
    } on PlatformFailure {
      // le fichier est de toute façon relu et réparé ci-dessous
    }
    return _finalize() ?? _lastFinished;
  }

  Recording? _finalize() {
    final id = _currentId;
    state = RecState.idle;
    level = 0;
    _currentId = null;
    final title = currentTitle;
    currentTitle = null;
    if (id == null) {
      notifyListeners();
      return null;
    }
    final path = store.wavPath(id);
    final repaired = repairWavHeader(path);
    if (repaired <= 0) {
      // Rien d'exploitable : on ne garde pas un fichier vide.
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
      notifyListeners();
      return null;
    }
    final created = DateTime.now().toUtc();
    final rec = Recording(
      id: id,
      title: title ?? defaultTitle(created),
      createdAt: created,
      durationMs: repaired,
      sizeBytes: File(path).lengthSync(),
    );
    store.save(rec);
    _lastFinished = rec;
    notifyListeners();
    return rec;
  }

  void _onEvent(Map<String, Object?> event) {
    if (event['name'] != 'recorderState') return;
    final data = event['data'];
    if (data is! Map) return;
    final name = data['state'] as String?;
    final elapsed = (data['elapsedMs'] as num?)?.toInt() ?? elapsedMs;
    final error = data['error'] as String?;
    if (name == 'stopped') {
      // Arrêt venu du système (espace plein, micro pris par un appel) : on conserve ce qui est fait.
      if (_currentId != null) {
        if (error != null) errorKey = _errorKeyFor(error);
        _finalize();
      }
      return;
    }
    if (_currentId == null) return;
    elapsedMs = elapsed;
    level = ((data['level'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
    state = name == 'paused' ? RecState.paused : RecState.recording;
    if (name != 'paused') _addLevel(elapsed, level);
    notifyListeners();
  }

  void _addLevel(int elapsed, double value) {
    final bucket = elapsed ~/ levelBucketMs;
    // Reprise d'un enregistrement déjà en cours : l'historique commence ici.
    if (levels.isEmpty) levelsOffset = bucket;
    final i = bucket - levelsOffset;
    if (i < 0) return;
    while (levels.length <= i) {
      levels.add(0);
    }
    if (value > levels[i]) levels[i] = value;
    if (levels.length > _maxLevels) {
      levels.removeRange(0, 1000);
      levelsOffset += 1000;
    }
  }

  static String _errorKeyFor(String code) {
    switch (code) {
      case 'permission':
      case 'no_mic':
      case 'busy':
      case 'no_space':
      case 'read_error':
        return 'err_rec_$code';
      default:
        return 'err_rec_unknown';
    }
  }

  void dismissError() {
    if (errorKey != null) {
      errorKey = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
