import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:andika/audio/wav_file.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('andika_wav_');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  String write(int announced, List<int> samples) {
    final path = '${dir.path}/t.wav';
    final data = Int16List.fromList(samples);
    final bytes = BytesBuilder()
      ..add(WavReader.buildHeader(announced))
      ..add(data.buffer.asUint8List());
    File(path).writeAsBytesSync(bytes.toBytes());
    return path;
  }

  test('l\'en-tête fait 44 octets et se relit', () {
    final header = WavReader.buildHeader(16000);
    expect(header.length, WavReader.headerSize);
    expect(WavReader.parseHeader(header), 16000);
  });

  test('ouverture et lecture d\'échantillons', () {
    final path = write(5, <int>[1, -2, 3, -4, 5]);
    final reader = WavReader.open(path);
    expect(reader.sampleCount, 5);
    expect(reader.read(0, 5), <int>[1, -2, 3, -4, 5]);
    expect(reader.read(2, 2), <int>[3, -4]);
    expect(reader.read(3, 10), <int>[-4, 5]);
    expect(reader.read(5, 1), isEmpty);
    expect(reader.durationMs, 0);
    reader.close();
  });

  test('un fichier tronqué est limité à ce qui est présent', () {
    final path = write(100, <int>[7, 8, 9]);
    final reader = WavReader.open(path);
    expect(reader.sampleCount, 3);
    reader.close();
  });

  test('un fichier qui n\'est pas un WAV est refusé', () {
    final path = '${dir.path}/x.wav';
    File(path).writeAsBytesSync(Uint8List(100));
    expect(() => WavReader.open(path), throwsFormatException);
  });

  test('un fichier trop court est refusé', () {
    final path = '${dir.path}/court.wav';
    File(path).writeAsBytesSync(Uint8List(10));
    expect(() => WavReader.open(path), throwsFormatException);
  });
}
