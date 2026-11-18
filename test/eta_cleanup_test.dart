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

  test('boucle dans un segment : réduite à deux répétitions', () {
    expect(collapseLoops('Merci Merci Merci Merci Merci'), 'Merci Merci');
    expect(collapseLoops('Bonjour à tous bonjour à tous bonjour à tous bonjour à tous bonjour à tous fin'),
        'Bonjour à tous bonjour à tous fin');
    expect(collapseLoops('a b a b a b a b'), 'a b a b');
  });

  test('boucle : un texte normal ou un simple « oui oui oui » reste intact', () {
    expect(collapseLoops('Une phrase normale sans boucle du tout ici'), 'Une phrase normale sans boucle du tout ici');
    expect(collapseLoops('Oui oui oui'), 'Oui oui oui');
    expect(collapseLoops('Non, non, non, c\'est faux'), 'Non, non, non, c\'est faux');
  });

  test('hallucinations : phrases parasites et marqueurs de bruit', () {
    expect(isHallucination("Sous-titres réalisés par la communauté d'Amara.org"), isTrue);
    expect(isHallucination('Merci d\'avoir regardé cette vidéo !'), isTrue);
    expect(isHallucination('Thanks for watching!'), isTrue);
    expect(isHallucination('[Musique]'), isTrue);
    expect(isHallucination('(Applaudissements)'), isTrue);
    expect(isHallucination('♪'), isTrue);
    expect(isHallucination('   '), isTrue);
    expect(isHallucination('Le parc a été créé en 2016.'), isFalse);
    expect(isHallucination('Merci beaucoup pour votre accueil.'), isFalse);
    expect(isHallucination('La musique congolaise est très riche.'), isFalse);
  });

  test('nettoyage complet : parasites retirés, texte utile conservé', () {
    final out = cleanTranscript([
      seg('Bonjour à tous.', 0),
      seg('Sous-titrage Société Radio-Canada', 1),
      seg('[Musique]', 2),
      seg('Merci Merci Merci Merci Merci Merci', 3),
      seg('Merci', 4),
      seg('Merci', 5),
      seg('Fin de l\'entretien.', 6),
    ]);
    expect(out.map((s) => s.text), ['Bonjour à tous.', 'Merci Merci', 'Merci', 'Merci', 'Fin de l\'entretien.']);
  });
}
