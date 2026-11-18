import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:andika/audio/wav_file.dart';
import 'package:andika/platform/platform_bridge.dart';
import 'package:andika/recorder/recorder_controller.dart';
import 'package:andika/recorder/recording.dart';
import 'package:andika/recorder/recording_store.dart';

const MethodChannel channel = MethodChannel('org.chadracklonde.andika/platform');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late RecordingStore store;
  late RecorderController rec;
  late List<String> calls;
  late bool micAllowed;
  late bool micGrant;
  String? startError;
  String? lastPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('andika_ctrl');
    store = RecordingStore(tmp.path);
    calls = <String>[];
    micAllowed = true;
    micGrant = true;
    startError = null;
    lastPath = null;
    PlatformBridge.instance.start();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'microphoneAllowed':
          return micAllowed;
        case 'requestMicrophone':
          return micGrant;
        case 'notificationsAllowed':
          return true;
        case 'recorderStart':
          if (startError != null) throw PlatformException(code: startError!, message: 'x');
          lastPath = (call.arguments as Map)['path'] as String;
          // Simule ce que fait Kotlin : un WAV dont l'en-tête n'a pas été finalisé.
          File(lastPath!)
            ..createSync(recursive: true)
            ..writeAsBytesSync(<int>[...WavReader.buildHeader(0), ...List<int>.filled(64000, 1)]);
          return null;
        case 'recorderStop':
          return <String, Object?>{'durationMs': 2000, 'path': lastPath};
        case 'recorderStatus':
          return <String, Object?>{'state': 'idle'};
        default:
          return null;
      }
    });
    rec = RecorderController(
      store: store,
      texts: () => const RecorderTexts(title: 'T', text: 'x', channelName: 'c'),
      defaultTitle: (t) => 'Enregistrement',
    );
    rec.attach();
  });

  tearDown(() {
    rec.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    tmp.deleteSync(recursive: true);
  });

  Future<void> sendEvent(Map<String, Object?> data) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('recorderState', data)),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  test('démarrer puis arrêter crée une fiche réparée', () async {
    expect(await rec.start(), isTrue);
    expect(rec.state, RecState.recording);
    await sendEvent(<String, Object?>{'state': 'recording', 'elapsedMs': 1500, 'level': 0.4});
    expect(rec.elapsedMs, 1500);
    expect(rec.level, closeTo(0.4, 1e-9));
    final saved = await rec.stop();
    expect(saved, isNotNull);
    expect(saved!.durationMs, 2000);
    expect(rec.state, RecState.idle);
    expect(store.list().single.id, saved.id);
    expect(declaredSamples(store.wavPath(saved.id)), 32000);
  });

  test('pause et reprise', () async {
    await rec.start();
    await rec.pause();
    expect(rec.state, RecState.paused);
    await rec.resume();
    expect(rec.state, RecState.recording);
    expect(calls, containsAllInOrder(<String>['recorderPause', 'recorderResume']));
  });

  test('autorisation refusée : pas d\'enregistrement', () async {
    micAllowed = false;
    micGrant = false;
    expect(await rec.start(), isFalse);
    expect(rec.errorKey, 'err_rec_permission');
    expect(calls, isNot(contains('recorderStart')));
  });

  test('autorisation accordée à la demande', () async {
    micAllowed = false;
    expect(await rec.start(), isTrue);
    expect(calls, contains('requestMicrophone'));
  });

  test('erreurs du micro traduites en clés de texte', () async {
    startError = 'busy';
    expect(await rec.start(), isFalse);
    expect(rec.errorKey, 'err_rec_busy');
    startError = 'bizarre';
    expect(await rec.start(), isFalse);
    expect(rec.errorKey, 'err_rec_unknown');
    expect(rec.state, RecState.idle);
  });

  test('arrêt venu du système (espace plein) : l\'enregistrement est conservé', () async {
    await rec.start();
    await sendEvent(<String, Object?>{
      'state': 'stopped',
      'elapsedMs': 2000,
      'level': 0.0,
      'error': 'no_space',
    });
    expect(rec.state, RecState.idle);
    expect(rec.errorKey, 'err_rec_no_space');
    expect(store.list(), hasLength(1));
    // L'arrêt demandé ensuite par l'utilisateur ne crée pas de doublon.
    final again = await rec.stop();
    expect(again, isNotNull);
    expect(store.list(), hasLength(1));
  });

  test('enregistrement vide : aucune fiche', () async {
    await rec.start();
    File(lastPath!).writeAsBytesSync(WavReader.buildHeader(0));
    expect(await rec.stop(), isNull);
    expect(store.list(), isEmpty);
    expect(File(lastPath!).existsSync(), isFalse);
  });

  test('historique du niveau : le plus fort de chaque tranche de 100 ms', () async {
    await rec.start();
    await sendEvent(<String, Object?>{'state': 'recording', 'elapsedMs': 30, 'level': 0.2});
    await sendEvent(<String, Object?>{'state': 'recording', 'elapsedMs': 80, 'level': 0.5});
    await sendEvent(<String, Object?>{'state': 'recording', 'elapsedMs': 350, 'level': 0.3});
    expect(rec.levelsOffset, 0);
    expect(rec.levels, <double>[0.5, 0, 0, 0.3]);
    // En pause, rien n'est ajouté.
    await sendEvent(<String, Object?>{'state': 'paused', 'elapsedMs': 400, 'level': 0.0});
    expect(rec.levels, hasLength(4));
    // Un nouvel enregistrement repart de zéro et porte un titre.
    await rec.stop();
    await rec.start();
    expect(rec.levels, isEmpty);
    expect(rec.currentTitle, 'Enregistrement');
  });

  test('chronomètre précis mm:ss,cc', () {
    expect(formatPrecise(0), '00:00,00');
    expect(formatPrecise(21234), '00:21,23');
    expect(formatPrecise(125990), '02:05,99');
    expect(formatPrecise(-5), '00:00,00');
  });
}
