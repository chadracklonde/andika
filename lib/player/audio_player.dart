import 'dart:async';

import '../platform/platform_bridge.dart';
import '../transcription/transcript.dart';

/// État du lecteur, tel que publié par Android.
class PlayerState {
  const PlayerState({
    this.positionMs = 0,
    this.durationMs = 0,
    this.playing = false,
    this.completed = false,
  });

  final int positionMs;
  final int durationMs;
  final bool playing;
  final bool completed;

  static PlayerState fromMap(Map<Object?, Object?> map) => PlayerState(
        positionMs: (map['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
        playing: map['playing'] as bool? ?? false,
        completed: map['completed'] as bool? ?? false,
      );
}

/// Indice du segment à surligner à [positionMs] : le dernier segment commencé,
/// ou -1 avant le premier. Les segments doivent être triés par début.
int segmentIndexAt(List<Segment> segments, int positionMs) {
  var lo = 0;
  var hi = segments.length - 1;
  var found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (segments[mid].startMs <= positionMs) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found;
}

/// Lecteur audio de la page résultat.
class AudioPlayerController {
  AudioPlayerController([PlatformBridge? bridge]) : _bridge = bridge ?? PlatformBridge.instance;

  final PlatformBridge _bridge;
  final StreamController<PlayerState> _states = StreamController<PlayerState>.broadcast();
  StreamSubscription<Map<String, Object?>>? _sub;
  PlayerState _last = const PlayerState();

  Stream<PlayerState> get states => _states.stream;
  PlayerState get state => _last;

  /// Charge le fichier ; retourne la durée en ms.
  Future<int> load(String path) async {
    _sub ??= _bridge.events.listen((event) {
      if (event['name'] != 'playerState') return;
      final data = event['data'];
      if (data is Map) {
        _last = PlayerState.fromMap(Map<Object?, Object?>.from(data));
        _states.add(_last);
      }
    });
    final duration = await _bridge.invoke<int>('playerLoad', <String, Object?>{'path': path});
    return duration ?? 0;
  }

  Future<void> play() => _bridge.invoke<void>('playerPlay');
  Future<void> pause() => _bridge.invoke<void>('playerPause');
  Future<void> seek(int positionMs) =>
      _bridge.invoke<void>('playerSeek', <String, Object?>{'positionMs': positionMs});
  Future<void> setSpeed(double speed) =>
      _bridge.invoke<void>('playerSpeed', <String, Object?>{'speed': speed});

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _bridge.invoke<void>('playerRelease');
    } catch (_) {}
    await _states.close();
  }
}
