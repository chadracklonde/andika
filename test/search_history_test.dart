import 'package:flutter_test/flutter_test.dart';

import 'package:andika/export/search.dart';
import 'package:andika/storage/job.dart';
import 'package:andika/transcription/transcript.dart';

Job job(String id, String title) => Job(
      id: id,
      title: title,
      createdAt: DateTime.utc(2026, 11, 18),
      durationMs: 60000,
      language: 'fr',
      modelId: 'tiny',
      status: JobStatus.done,
    );

Segment seg(int start, String text) => Segment(startMs: start, endMs: start + 1000, text: text);

void main() {
  final jobs = <Job>[job('a', 'Entretien évêque'), job('b', 'Réunion Kindu')];
  final texts = <String, List<Segment>>{
    'a': <Segment>[seg(0, 'Bonjour à tous.'), seg(5000, 'La cérémonie a eu lieu à Kindu hier.')],
    'b': <Segment>[seg(0, 'Ordre du jour : KINDU et Lubutu.')],
  };
  List<Segment> load(String id) => texts[id] ?? <Segment>[];

  test('trouve sans tenir compte des accents ni de la casse, dans toutes les transcriptions', () {
    final hits = searchHistory(jobs, load, 'kindu');
    // « Réunion Kindu » (titre) puis deux passages.
    expect(hits.map((h) => '${h.job.id}:${h.segmentIndex}').toList(), <String>['a:1', 'b:-1', 'b:0']);
    final first = hits.first;
    expect(first.startMs, 5000);
    expect(first.match, 'Kindu');
    expect(first.before, 'La cérémonie a eu lieu à ');
    expect(first.after, ' hier.');
  });

  test('« evêque » trouve « évêque » dans un titre', () {
    final hits = searchHistory(jobs, load, 'eveque');
    expect(hits.single.job.id, 'a');
    expect(hits.single.segmentIndex, -1);
  });

  test('moins de 2 lettres : aucun résultat', () {
    expect(searchHistory(jobs, load, 'k'), isEmpty);
    expect(searchHistory(jobs, load, '  '), isEmpty);
  });

  test('extrait raccourci avec des points de suspension', () {
    final long = 'a' * 100 + ' Lubutu ' + 'b' * 100;
    final hits = searchHistory(
      <Job>[jobs.first],
      (_) => <Segment>[seg(0, long)],
      'lubutu',
      context: 10,
    );
    expect(hits.single.before.startsWith('…'), isTrue);
    expect(hits.single.after.endsWith('…'), isTrue);
    expect(hits.single.match, 'Lubutu');
  });

  test('s\'arrête au nombre maximal de résultats', () {
    final many = List<Segment>.generate(50, (i) => seg(i * 1000, 'Kindu $i'));
    final hits = searchHistory(<Job>[jobs.first], (_) => many, 'kindu', maxHits: 10);
    expect(hits, hasLength(10));
  });
}
