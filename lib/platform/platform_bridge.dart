import 'dart:async';

import 'package:flutter/services.dart';

/// Fichier choisi par l'utilisateur (sélecteur ou partage depuis une autre application).
class PickedFile {
  const PickedFile({required this.uri, required this.name, required this.size});

  factory PickedFile.fromMap(Map<Object?, Object?> map) {
    return PickedFile(
      uri: map['uri'] as String,
      name: (map['name'] as String?) ?? 'audio',
      size: (map['size'] as num?)?.toInt() ?? -1,
    );
  }

  /// Adresse `content://` ou `file://` lisible par le décodeur Android.
  final String uri;
  final String name;

  /// Taille en octets, -1 si inconnue.
  final int size;
}

/// Informations sur le téléphone, utiles pour choisir les modèles.
class DeviceInfo {
  const DeviceInfo({
    required this.totalRamBytes,
    required this.availableRamBytes,
    required this.freeStorageBytes,
    required this.sdkInt,
    required this.abi,
    required this.model,
  });

  factory DeviceInfo.fromMap(Map<Object?, Object?> map) {
    return DeviceInfo(
      totalRamBytes: (map['totalRamBytes'] as num?)?.toInt() ?? 0,
      availableRamBytes: (map['availableRamBytes'] as num?)?.toInt() ?? 0,
      freeStorageBytes: (map['freeStorageBytes'] as num?)?.toInt() ?? 0,
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      abi: (map['abi'] as String?) ?? '',
      model: (map['model'] as String?) ?? '',
    );
  }

  final int totalRamBytes;
  final int availableRamBytes;
  final int freeStorageBytes;
  final int sdkInt;
  final String abi;
  final String model;
}

/// Dossiers privés de l'application.
class AppPaths {
  const AppPaths({required this.files, required this.cache});

  final String files;
  final String cache;
}

/// Résultat du décodage d'un fichier audio ou vidéo.
class DecodedAudio {
  const DecodedAudio({required this.durationMs, required this.sampleCount});

  final int durationMs;
  final int sampleCount;
}

/// Erreur renvoyée par le code Android. [code] vaut par exemple `no_audio`,
/// `unsupported`, `read_error`, `decode_error`, `cancelled` ou `busy`.
class PlatformFailure implements Exception {
  PlatformFailure(this.code, this.message);

  final String code;
  final String message;

  bool get isCancelled => code == 'cancelled';

  @override
  String toString() => 'PlatformFailure($code): $message';
}

/// Pont vers le code Kotlin (voir PlatformBridge.kt).
class PlatformBridge {
  PlatformBridge._();

  static final PlatformBridge instance = PlatformBridge._();

  static const MethodChannel _channel = MethodChannel('org.chadracklonde.andika/platform');

  final StreamController<int> _decodeProgress = StreamController<int>.broadcast();
  final StreamController<PickedFile> _shared = StreamController<PickedFile>.broadcast();
  final StreamController<Map<String, Object?>> _events =
      StreamController<Map<String, Object?>>.broadcast();
  bool _started = false;

  /// À appeler une fois au démarrage.
  void start() {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler(_onCall);
  }

  /// Progression du décodage, de 0 à 100.
  Stream<int> get decodeProgress => _decodeProgress.stream;

  /// Fichier reçu pendant que l'application tourne (« Partager vers Andika »).
  Stream<PickedFile> get sharedFiles => _shared.stream;

  /// Événements divers venant d'Android (service, lecteur...) : {'name': ..., 'data': ...}.
  Stream<Map<String, Object?>> get events => _events.stream;

  Future<Object?> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'decodeProgress':
        _decodeProgress.add((call.arguments as num).toInt());
        break;
      case 'shared':
        _shared.add(PickedFile.fromMap(Map<Object?, Object?>.from(call.arguments as Map)));
        break;
      default:
        _events.add(<String, Object?>{'name': call.method, 'data': call.arguments});
    }
    return null;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PlatformException catch (e) {
      throw PlatformFailure(e.code, e.message ?? e.code);
    } on MissingPluginException {
      throw PlatformFailure('unavailable', 'Fonction Android indisponible');
    }
  }

  /// Ouvre le sélecteur de fichiers. Retourne null si l'utilisateur annule.
  Future<PickedFile?> pickAudio() {
    return _guard<PickedFile?>(() async {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('pickAudio');
      return map == null ? null : PickedFile.fromMap(map);
    });
  }

  /// Fichier avec lequel l'application a été ouverte (partage), une seule fois.
  Future<PickedFile?> getInitialShare() {
    return _guard<PickedFile?>(() async {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('getInitialShare');
      return map == null ? null : PickedFile.fromMap(map);
    });
  }

  Future<DeviceInfo> getDeviceInfo() {
    return _guard<DeviceInfo>(() async {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('getDeviceInfo');
      return DeviceInfo.fromMap(map ?? <Object?, Object?>{});
    });
  }

  Future<AppPaths> getPaths() {
    return _guard<AppPaths>(() async {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>('getPaths');
      return AppPaths(
        files: map?['files'] as String? ?? '',
        cache: map?['cache'] as String? ?? '',
      );
    });
  }

  /// Décode le fichier en WAV 16 kHz mono vers [outPath].
  Future<DecodedAudio> decodeToWav({required String uri, required String outPath}) {
    return _guard<DecodedAudio>(() async {
      final map = await _channel.invokeMethod<Map<Object?, Object?>>(
        'decodeToWav',
        <String, Object?>{'uri': uri, 'outPath': outPath},
      );
      return DecodedAudio(
        durationMs: (map?['durationMs'] as num?)?.toInt() ?? 0,
        sampleCount: (map?['sampleCount'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Future<void> cancelDecode() {
    return _guard<void>(() => _channel.invokeMethod<void>('cancelDecode'));
  }

  /// Appel générique pour les fonctions ajoutées par les lots suivants.
  Future<T?> invoke<T>(String method, [Object? arguments]) {
    return _guard<T?>(() => _channel.invokeMethod<T>(method, arguments));
  }
}
