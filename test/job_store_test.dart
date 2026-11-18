import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:andika/player/audio_player.dart';
import 'package:andika/storage/job.dart';
import 'package:andika/storage/job_store.dart';
import 'package:andika/transcription/segment_log.dart';
import 'package:andika/transcription/transcript.dart';

Job job(String id, DateTime t, {JobStatus status = JobStatus.done}) => Job(
    id: id,
    title: 'Entretien $id',
    createdAt: t,
    durationMs: 60000,
    language: 'fr',
    modelId: 'base',
    status: status);

void main() {
  late Directory tmp;
  late JobStore store;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('andika_jobs');
    store = JobStore(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('fiche : aller-retour JSON', () {
    final j = job('a', DateTime.utc(2026, 11, 18, 4, 0));
    store.save(j);
    final back = store.load('a')!;
    expect(back.title, j.title);
    expect(back.createdAt, j.createdAt);
    expect(back.status, JobStatus.done);
  });

  test('liste : la plus récente d\'abord', () {
    store.save(job('old', DateTime.utc(2026, 1, 1)));
    store.save(job('new', DateTime.utc(2026, 6, 1)));
    expect(store.list().map((j) => j.id), ['new', 'old']);
  });

  test('identifiants uniques à la même seconde', () {
    final t = DateTime.utc(2026, 1, 1, 10);
    final a = store.newId(t);
    store.save(job(a, t));
    expect(store.newId(t), isNot(a));
  });

  test('reprise : une tâche « en cours » devient interrompue', () {
    store.save(job('r', DateTime.utc(2026, 1, 1), status: JobStatus.running));
    expect(store.markInterrupted(), 1);
    expect(store.load('r')!.status, JobStatus.interrupted);
  });

  test('texte : journal brut, puis version relue prioritaire', () {
    store.save(job('t', DateTime.utc(2026, 1, 1)));
    store.log('t').append(const ChunkRecord(index: 0, language: 'fr', segments: [
      Segment(startMs: 0, endMs: 1000, text: 'brut'),
    ]));
    expect(store.loadTranscript('t').single.text, 'brut');
    store.saveTranscript('t', const [Segment(startMs: 0, endMs: 1000, text: 'corrigé')]);
    expect(store.loadTranscript('t').single.text, 'corrigé');
  });

  test('transcription abîmée : retour au journal', () {
    store.save(job('x', DateTime.utc(2026, 1, 1)));
    store.log('x').append(const ChunkRecord(index: 0, language: 'fr', segments: [
      Segment(startMs: 0, endMs: 1, text: 'brut'),
    ]));
    File('${tmp.path}/jobs/x/transcript.json').writeAsStringSync('[{"s":');
    expect(store.loadTranscript('x').single.text, 'brut');
  });

  test('suppression de l\'audio seul, puis de tout', () {
    store.save(job('d', DateTime.utc(2026, 1, 1)));
    Directory('${tmp.path}/audio').createSync();
    File(store.audioPath('d')).writeAsBytesSync([1, 2, 3]);
    expect(store.audioBytes(), 3);
    store.deleteAudio('d');
    expect(store.audioBytes(), 0);
    expect(store.load('d')!.hasAudio, isFalse);
    store.delete('d');
    expect(store.load('d'), isNull);
  });

  test('segment à surligner selon la position', () {
    const segs = [
      Segment(startMs: 0, endMs: 1000, text: 'a'),
      Segment(startMs: 2000, endMs: 3000, text: 'b'),
      Segment(startMs: 5000, endMs: 6000, text: 'c'),
    ];
    expect(segmentIndexAt(segs, -1), -1);
    expect(segmentIndexAt(segs, 0), 0);
    expect(segmentIndexAt(segs, 1500), 0);
    expect(segmentIndexAt(segs, 2000), 1);
    expect(segmentIndexAt(segs, 9000), 2);
    expect(segmentIndexAt(const [], 100), -1);
  });
}
