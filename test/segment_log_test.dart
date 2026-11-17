import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:andika/transcription/segment_log.dart';
import 'package:andika/transcription/transcript.dart';

void main() {
  late Directory tmp;
  late SegmentLog log;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('andika_log');
    log = SegmentLog('${tmp.path}/job.jsonl');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('écriture puis relecture, avec accents', () {
    log.append(const ChunkRecord(index: 0, language: 'fr', segments: [
      Segment(startMs: 0, endMs: 1500, text: 'Bonjour à tous, très heureux.'),
    ]));
    log.append(const ChunkRecord(index: 1, language: 'fr', segments: [
      Segment(startMs: 12000, endMs: 14000, text: 'Mbote'),
    ]));
    expect(log.completedChunks(), {0, 1});
    expect(log.allSegments().first.text, 'Bonjour à tous, très heureux.');
    expect(log.allSegments().last.startMs, 12000);
  });

  test('une ligne tronquée est ignorée (reprise après arrêt brutal)', () {
    log.append(const ChunkRecord(index: 0, language: 'fr', segments: []));
    File(log.path).writeAsStringSync('{"c":1,"l":"fr","g":[{"s":1', mode: FileMode.append);
    expect(log.completedChunks(), {0});
  });

  test('morceau sans parole : présent dans le journal, sans segment', () {
    log.append(const ChunkRecord(index: 3, language: '', segments: []));
    expect(log.completedChunks(), {3});
    expect(log.allSegments(), isEmpty);
  });

  test('langue dominante', () {
    log.append(const ChunkRecord(index: 0, language: 'fr', segments: []));
    log.append(const ChunkRecord(index: 1, language: 'sw', segments: []));
    log.append(const ChunkRecord(index: 2, language: 'fr', segments: []));
    expect(log.dominantLanguage(), 'fr');
  });

  test('segments triés par temps et fichier absent', () {
    expect(SegmentLog('${tmp.path}/none.jsonl').read(), isEmpty);
    log.append(const ChunkRecord(index: 1, language: 'fr', segments: [
      Segment(startMs: 500, endMs: 900, text: 'b'),
    ]));
    log.append(const ChunkRecord(index: 0, language: 'fr', segments: [
      Segment(startMs: 100, endMs: 400, text: 'a'),
    ]));
    expect(log.allSegments().map((s) => s.text), ['a', 'b']);
  });
}
