import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:andika/app/controller.dart';
import 'package:andika/audio/wav_file.dart';
import 'package:andika/recorder/recorder_controller.dart';
import 'package:andika/storage/job.dart';
import 'package:andika/transcription/transcript.dart';
import 'package:andika/ui/home_screen.dart';
import 'package:andika/ui/recorder_screen.dart';
import 'package:andika/ui/recordings_screen.dart';
import 'package:andika/ui/result_screen.dart';
import 'package:andika/ui/search_screen.dart';

const MethodChannel channel = MethodChannel('org.chadracklonde.andika/platform');

/// Parcours de l'interface rejoués avec un faux Android : ils révèlent les erreurs
/// d'affichage (par exemple une assertion du cadre Flutter) que l'analyse ne voit pas.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AppController c;
  String? lastPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('andika_ui');
    Directory('${tmp.path}/files').createSync();
    Directory('${tmp.path}/cache').createSync();
    lastPath = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getPaths':
          return <String, Object?>{'files': '${tmp.path}/files', 'cache': '${tmp.path}/cache'};
        case 'getDeviceInfo':
          return <String, Object?>{'totalRamBytes': 4000000000, 'sdkInt': 34, 'abi': 'arm64-v8a'};
        case 'getInitialShare':
          return <Object?>[];
        case 'microphoneAllowed':
        case 'notificationsAllowed':
          return true;
        case 'recorderStart':
          lastPath = (call.arguments as Map)['path'] as String;
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
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    tmp.deleteSync(recursive: true);
  });

  /// Laisse les opérations réelles (fichiers) se terminer, puis redessine.
  Future<void> settle(WidgetTester tester, {int ms = 400}) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump(Duration(milliseconds: ms));
  }

  Future<void> boot(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    c = AppController();
    await tester.runAsync(() => c.init());
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  }

  Future<void> sendLevel(WidgetTester tester, int elapsedMs, {String state = 'recording'}) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall(
        'recorderState',
        <String, Object?>{'state': state, 'elapsedMs': elapsedMs, 'level': 0.3},
      )),
      (_) {},
    );
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('accueil : enregistrer, repère, pause, reprise, ✓ vers la bibliothèque', (tester) async {
    await boot(tester);
    expect(find.byKey(const Key('record_button')), findsOneWidget);
    expect(find.byKey(const Key('transcribe_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('record_button')));
    await settle(tester);
    expect(find.byType(RecorderScreen), findsOneWidget);
    expect(c.recorder.state, RecState.recording, reason: 'le bouton rouge de l\'accueil démarre tout de suite');

    for (var ms = 100; ms <= 1500; ms += 100) {
      await sendLevel(tester, ms);
    }
    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.recorder.markers, <int>[1500]);

    // Pause puis reprise par le grand bouton de la pastille.
    await tester.tap(find.byKey(const Key('main_button')));
    await settle(tester);
    expect(c.recorder.state, RecState.paused);
    await tester.tap(find.byKey(const Key('main_button')));
    await settle(tester);
    expect(c.recorder.state, RecState.recording);

    await tester.tap(find.byIcon(Icons.check));
    await settle(tester);
    expect(c.recorder.state, RecState.idle);
    expect(find.byType(RecordingsScreen), findsOneWidget);
    expect(c.recordings, hasLength(1));
    expect(c.recordings.single.markers, <int>[1500]);

    // Ligne dépliée : le repère est proposé.
    await tester.tap(find.byKey(Key('rec_row_${c.recordings.single.id}')));
    await settle(tester);
    expect(find.byType(ActionChip), findsOneWidget);
    await finish(tester);
  });

  testWidgets('enregistrement en cours : retour à l\'accueil, chronomètre qui avance, retour au dictaphone',
      (tester) async {
    await boot(tester);
    await tester.tap(find.byKey(const Key('record_button')));
    await settle(tester);
    await sendLevel(tester, 500);
    // Retour à l'accueil : l'enregistrement continue.
    await tester.pageBack();
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(c.recorder.active, isTrue);
    // Le micro envoie beaucoup d'événements pendant que l'accueil est affiché.
    for (var ms = 600; ms <= 3000; ms += 50) {
      await sendLevel(tester, ms);
    }
    expect(find.textContaining('0:03'), findsWidgets);
    // Le bouton rouge devient « Enregistrement · 0:03 » et rouvre le dictaphone sans recommencer.
    await tester.tap(find.byKey(const Key('record_button')));
    await settle(tester);
    expect(find.byType(RecorderScreen), findsOneWidget);
    expect(c.recorder.state, RecState.recording);
    await tester.tap(find.byIcon(Icons.check));
    await settle(tester);
    expect(c.recordings, hasLength(1));
    await finish(tester);
  });

  testWidgets('bibliothèque : bouton rouge, enregistrer, ✓, retour à la liste', (tester) async {
    await boot(tester);
    await tester.tap(find.byIcon(Icons.library_music_outlined));
    await settle(tester);
    expect(find.byType(RecordingsScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('library_record_button')));
    await settle(tester);
    expect(find.byType(RecorderScreen), findsOneWidget);
    expect(c.recorder.state, RecState.recording);
    await sendLevel(tester, 800);
    await tester.tap(find.byIcon(Icons.check));
    await settle(tester);
    expect(find.byType(RecorderScreen), findsNothing);
    expect(find.byType(RecordingsScreen), findsOneWidget);
    expect(c.recordings, hasLength(1));
    await finish(tester);
  });

  testWidgets('recherche globale puis ouverture de la transcription', (tester) async {
    await boot(tester);
    c.jobs.save(Job(
      id: 'j1',
      title: 'Entretien évêque',
      createdAt: DateTime.utc(2026, 11, 18),
      durationMs: 60000,
      language: 'fr',
      modelId: 'tiny',
      status: JobStatus.done,
      hasAudio: false,
    ));
    c.jobs.saveTranscript('j1', const <Segment>[
      Segment(startMs: 0, endMs: 2000, text: 'Bonjour à tous.'),
      Segment(startMs: 5000, endMs: 8000, text: 'La cérémonie a eu lieu à Kindu hier.'),
    ]);
    c.refreshHistory();
    await settle(tester);

    await tester.tap(find.byIcon(Icons.search));
    await settle(tester);
    expect(find.byType(SearchScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'kindu');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Entretien évêque'), findsOneWidget);

    await tester.tap(find.text('Entretien évêque'));
    await settle(tester);
    expect(find.byType(ResultScreen), findsOneWidget);
    await finish(tester);
  });
}
