import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:andika/audio/wav_file.dart';
import 'package:andika/recorder/recording.dart';
import 'package:andika/recorder/recording_store.dart';

/// Écrit un WAV Andika : l'en-tête annonce [declared] échantillons, le fichier en contient [actual]
/// (plus [extraBytes] octets isolés).
File writeWav(String path, {required int declared, required int actual, int extraBytes = 0}) {
  final data = Uint8List(actual * 2 + extraBytes);
  for (var i = 0; i < data.length; i++) {
    data[i] = i % 251;
  }
  final bytes = BytesBuilder()
    ..add(WavReader.buildHeader(declared))
    ..add(data);
  final f = File(path)..createSync(recursive: true);
  f.writeAsBytesSync(bytes.toBytes());
  return f;
}

void main() {
  late Directory tmp;
  late RecordingStore store;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('andika_rec');
    store = RecordingStore(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('réparation : en-tête à zéro après un arrêt brutal', () {
    final f = writeWav('${tmp.path}/a.wav', declared: 0, actual: 32000);
    expect(repairWavHeader(f.path), 2000);
    expect(declaredSamples(f.path), 32000);
    expect(f.lengthSync(), 44 + 64000);
  });

  test('réparation : le contenu audio est conservé', () {
    final f = writeWav('${tmp.path}/a.wav', declared: 0, actual: 1000);
    final before = f.readAsBytesSync().sublist(44);
    repairWavHeader(f.path);
    expect(f.readAsBytesSync().sublist(44), before);
  });

  test('réparation : un fichier déjà juste n\'est pas touché', () {
    final f = writeWav('${tmp.path}/a.wav', declared: 16000, actual: 16000);
    final stamp = f.lastModifiedSync();
    expect(repairWavHeader(f.path), 1000);
    expect(f.lastModifiedSync(), stamp);
  });

  test('réparation : un octet isolé est écarté', () {
    final f = writeWav('${tmp.path}/a.wav', declared: 0, actual: 8000, extraBytes: 1);
    expect(repairWavHeader(f.path), 500);
    expect(f.lengthSync(), 44 + 16000);
  });

  test('réparation : fichier trop court ou absent', () {
    final f = File('${tmp.path}/b.wav')..writeAsBytesSync(Uint8List(30));
    expect(repairWavHeader(f.path), -1);
    expect(repairWavHeader('${tmp.path}/absent.wav'), -1);
    final empty = writeWav('${tmp.path}/c.wav', declared: 0, actual: 0);
    expect(repairWavHeader(empty.path), -1);
  });

  test('réparation : WavReader lit tout le fichier réparé', () {
    final f = writeWav('${tmp.path}/a.wav', declared: 0, actual: 4000);
    repairWavHeader(f.path);
    final r = WavReader.open(f.path);
    expect(r.sampleCount, 4000);
    r.close();
  });

  test('identifiants : uniques et triés par date', () {
    final t = DateTime.utc(2026, 11, 18, 10, 30, 5);
    final a = store.newId(t);
    expect(a, 'rec-20261118-103005');
    writeWav(store.wavPath(a), declared: 16000, actual: 16000);
    expect(store.newId(t), 'rec-20261118-103005-1');
  });

  Recording rec(String id, DateTime t) =>
      Recording(id: id, title: 'Entretien $id', createdAt: t, durationMs: 1000, sizeBytes: 32044);

  test('liste : plus récent d\'abord, sans audio = ignoré', () {
    store.save(rec('rec-1', DateTime.utc(2026, 11, 1)));
    store.save(rec('rec-2', DateTime.utc(2026, 11, 2)));
    store.save(rec('rec-3', DateTime.utc(2026, 11, 3)));
    writeWav(store.wavPath('rec-1'), declared: 16000, actual: 16000);
    writeWav(store.wavPath('rec-2'), declared: 16000, actual: 16000);
    expect(store.list().map((r) => r.id), <String>['rec-2', 'rec-1']);
  });

  test('renommer et supprimer', () {
    final r = rec('rec-1', DateTime.utc(2026, 11, 1));
    store.save(r);
    writeWav(store.wavPath('rec-1'), declared: 16000, actual: 16000);
    store.rename(r, '  Interview Lomami  ');
    expect(store.load('rec-1')!.title, 'Interview Lomami');
    store.rename(store.load('rec-1')!, '   ');
    expect(store.load('rec-1')!.title, 'Interview Lomami');
    expect(store.totalBytes(), 44 + 32000);
    store.delete('rec-1');
    expect(store.list(), isEmpty);
    expect(File(store.wavPath('rec-1')).existsSync(), isFalse);
  });

  test('fiche abîmée : ignorée sans planter', () {
    Directory('${tmp.path}/recordings').createSync(recursive: true);
    File('${tmp.path}/recordings/rec-x.json').writeAsStringSync('{pas du json');
    writeWav(store.wavPath('rec-x'), declared: 16000, actual: 16000);
    expect(store.list(), isEmpty);
  });

  test('récupération : un enregistrement sans fiche est retrouvé et réparé', () {
    writeWav(store.wavPath('rec-orphan'), declared: 0, actual: 48000);
    writeWav(store.wavPath('rec-vide'), declared: 0, actual: 0);
    writeWav(store.wavPath('rec-actif'), declared: 0, actual: 16000);
    final found = store.recoverOrphans(
      titleFor: (t) => 'Récupéré',
      skipPath: store.wavPath('rec-actif'),
    );
    expect(found.map((r) => r.id), <String>['rec-orphan']);
    expect(found.single.durationMs, 3000);
    expect(store.list().map((r) => r.id), <String>['rec-orphan']);
    expect(File(store.wavPath('rec-vide')).existsSync(), isFalse); // rien d'exploitable
    expect(File(store.wavPath('rec-actif')).existsSync(), isTrue); // en cours : intact
  });

  test('titre par défaut : date courte', () {
    final text = formatShortDate(DateTime.utc(2026, 11, 18, 10, 30));
    expect(RegExp(r'^\d{2}/\d{2} \d{2}:\d{2}$').hasMatch(text), isTrue);
  });
}
