import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:andika/audio/chunk_planner.dart';

Float32List frames(List<double> values) => Float32List.fromList(values);

void main() {
  group('energyFromSamples', () {
    test('un signal constant donne son amplitude, dernier frame partiel compris', () {
      final samples = Int16List(kFrameSamples + 800)..fillRange(0, kFrameSamples + 800, 1000);
      final rms = energyFromSamples(samples);
      expect(rms.length, 2);
      expect(rms[0], closeTo(1000, 0.01));
      expect(rms[1], closeTo(1000, 0.01));
    });

    test('le silence donne zéro', () {
      expect(energyFromSamples(Int16List(3200)), <double>[0, 0]);
    });
  });

  group('silenceThreshold', () {
    test('parole régulière : plafonné à 40 % de la médiane', () {
      expect(silenceThreshold(frames(List<double>.filled(100, 1000))), closeTo(400, 0.001));
    });

    test('bruit de fond léger : 2,5 fois le bruit', () {
      final values = <double>[...List<double>.filled(30, 100), ...List<double>.filled(70, 3000)];
      expect(silenceThreshold(frames(values)), closeTo(250, 0.001));
    });

    test('enregistrement vide : valeur par défaut', () {
      expect(silenceThreshold(Float32List(0)), 50);
    });
  });

  group('planChunks', () {
    test('un enregistrement court reste en un seul morceau', () {
      final plan = planChunks(frames(List<double>.filled(200, 1000)), 320000);
      expect(plan.chunks.length, 1);
      expect(plan.chunks.first.startSample, 0);
      expect(plan.chunks.first.endSample, 320000);
    });

    test('rien à découper si l\'audio est vide', () {
      expect(planChunks(Float32List(0), 0).chunks, isEmpty);
    });

    test('coupe dans les silences', () {
      final values = List<double>.filled(600, 1000);
      values[250] = 20;
      values[520] = 20;
      final plan = planChunks(frames(values), 960000);
      final bounds = plan.chunks.map((c) => <int>[c.startSample, c.endSample]).toList();
      expect(bounds, <List<int>>[
        <int>[0, 400800],
        <int>[400800, 832800],
        <int>[832800, 960000],
      ]);
      expect(plan.chunks.map((c) => c.index), <int>[0, 1, 2]);
    });

    test('sans silence, les morceaux font au plus 28 secondes (plus un demi-frame)', () {
      final plan = planChunks(frames(List<double>.filled(600, 1000)), 960000);
      expect(plan.chunks.length, 3);
      for (final chunk in plan.chunks) {
        expect(chunk.sampleCount, lessThanOrEqualTo(448800));
        expect(chunk.sampleCount, greaterThan(0));
      }
    });

    test('les morceaux se suivent sans trou ni chevauchement', () {
      final plan = planChunks(frames(List<double>.filled(900, 800)), 1440000);
      expect(plan.chunks.first.startSample, 0);
      expect(plan.chunks.last.endSample, 1440000);
      for (var i = 1; i < plan.chunks.length; i++) {
        expect(plan.chunks[i].startSample, plan.chunks[i - 1].endSample);
      }
    });

    test('suppression des silences : les morceaux silencieux sont ignorés', () {
      final values = <double>[...List<double>.filled(200, 1000), ...List<double>.filled(700, 10)];
      final all = planChunks(frames(values), 1440000);
      final speechOnly = planChunks(frames(values), 1440000, skipSilence: true);
      expect(all.chunks.length, 4);
      expect(speechOnly.chunks.length, 1);
      expect(speechOnly.chunks.first.startSample, 0);
      expect(speechOnly.chunks.first.index, 0);
    });

    test('un morceau conserve sa position d\'origine quand on saute des silences', () {
      final values = <double>[...List<double>.filled(300, 10), ...List<double>.filled(300, 1000)];
      final plan = planChunks(frames(values), 960000, skipSilence: true);
      expect(plan.chunks, isNotEmpty);
      expect(plan.chunks.first.startMs, greaterThan(0));
    });
  });
}
