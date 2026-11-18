import 'package:flutter_test/flutter_test.dart';

import 'package:andika/transcription/cleanup.dart';
import 'package:andika/transcription/eta.dart';
import 'package:andika/transcription/transcript.dart';

Segment seg(String t, int i) => Segment(startMs: i * 1000, endMs: i * 1000 + 900, text: t);

void main() {
  test('estimation : rien avant assez de morceaux, puis rythme moyen', () {
    var now = DateTime.utc(2026, 1, 1);
    final eta = EtaEstimator(clock: () => now);
    expect(eta.update(0, 10), isNull); // départ
    now = now.add(const Duration(seconds: 20));
    expect(eta.update(1, 10), isNull); // un seul morceau : trop tôt
    now = now.add(const Duration(seconds: 20));
    final left = eta.update(2, 10)!; // 20 s par morceau, 8 restants
    expect(left, const Duration(seconds: 160));
    expect(eta.update(10, 10), isNull);
  });

  test('estimation : reprise avec des morceaux déjà faits', () {
    var now = DateTime.utc(2026, 1, 1);
    final eta = EtaEstimator(clock: () => now);
    eta.update(5, 10);
    now = now.add(const Duration(seconds: 10));
    eta.update(6, 10);
    now = now.add(const Duration(seconds: 10));
    expect(eta.update(7, 10), const Duration(seconds: 30));
  });

  test('découpage heures/minutes', () {
    expect(splitEta(const Duration(seconds: 61)), (hours: 0, minutes: 2));
    expect(splitEta(const Duration(minutes: 65)), (hours: 1, minutes: 5));
  });

  test('répétitions : au plus 2 de suite, casse et ponctuation ignorées', () {
    final out = collapseRepeats([
      seg('Merci.', 0), seg('merci', 1), seg('Merci !', 2), seg('MERCI', 3),
      seg('Bonjour', 4), seg('Merci', 5),
    ]);
    expect(out.map((s) => s.text), ['Merci.', 'merci', 'Bonjour', 'Merci']);
  });

  test('segments vides retirés, textes distincts conservés', () {
    final out = collapseRepeats([seg('a', 0), seg('  ', 1), seg('b', 2)]);
    expect(out.map((s) => s.text), ['a', 'b']);
  });
}
