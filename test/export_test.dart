import 'package:flutter_test/flutter_test.dart';

import 'package:andika/export/exporters.dart';
import 'package:andika/export/search.dart';
import 'package:andika/transcription/transcript.dart';

const segs = [
  Segment(startMs: 0, endMs: 2500, text: ' Bonjour à tous. '),
  Segment(startMs: 2500, endMs: 3000, text: '   '),
  Segment(startMs: 65320, endMs: 70000, text: 'Mbote na bino.'),
];

void main() {
  test('format de temps SRT', () {
    expect(srtTime(0), '00:00:00,000');
    expect(srtTime(65320), '00:01:05,320');
    expect(srtTime(3723004), '01:02:03,004');
    expect(srtTime(-5), '00:00:00,000');
  });

  test('format de temps affiché', () {
    expect(clockTime(65000), '1:05');
    expect(clockTime(3725000), '1:02:05');
  });

  test('texte brut continu et horodaté, segments vides ignorés', () {
    expect(toPlainText(segs), 'Bonjour à tous. Mbote na bino.');
    expect(toPlainText(segs, timestamps: true), '[0:00] Bonjour à tous.\n[1:05] Mbote na bino.');
  });

  test('SRT : numérotation, durées valides, pas de chevauchement', () {
    final srt = toSrt(const [
      Segment(startMs: 0, endMs: 3000, text: 'a'),
      Segment(startMs: 2000, endMs: 2000, text: 'b'),
    ]);
    expect(srt,
        '1\n00:00:00,000 --> 00:00:02,000\na\n\n2\n00:00:02,000 --> 00:00:02,500\nb\n\n');
  });

  test('nom de fichier sûr', () {
    expect(safeFileName('Entretien: Évêque/Kindu?'), 'Entretien Évêque Kindu');
    expect(safeFileName('  ...  '), 'transcription');
    expect(safeFileName(''), 'transcription');
    expect(safeFileName('a' * 200).length, lessThanOrEqualTo(80));
  });

  test('recherche sans accent ni casse, occurrences multiples', () {
    const list = [
      Segment(startMs: 0, endMs: 1, text: 'Été à Kindu, été chaud'),
      Segment(startMs: 2, endMs: 3, text: 'Rien ici'),
    ];
    final hits = searchSegments(list, 'ete');
    expect(hits.length, 2);
    expect(hits.first.segmentIndex, 0);
    expect(hits.first.start, 0);
    expect(hits.last.start, 13);
    expect(searchSegments(list, ' '), isEmpty);
    expect(searchSegments(list, 'absent'), isEmpty);
  });
}
