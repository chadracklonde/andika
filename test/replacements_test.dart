import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:andika/extras/replacements.dart';
import 'package:andika/transcription/transcript.dart';

void main() {
  test('mots entiers uniquement', () {
    const rules = [Replacement(from: 'Kin', to: 'X')];
    expect(applyReplacements('Kindu et Kin.', rules), 'Kindu et X.');
  });

  test('insensible à la casse par défaut, sensible sur demande', () {
    expect(applyReplacements('kindu Kindu', const [Replacement(from: 'kindu', to: 'Kindu')]),
        'Kindu Kindu');
    expect(
        applyReplacements('kindu Kindu',
            const [Replacement(from: 'Kindu', to: 'KINDU', matchCase: true)]),
        'kindu KINDU');
  });

  test('accents et apostrophes', () {
    expect(applyReplacements('l\'évêque Mande', const [Replacement(from: 'évêque', to: 'Mgr')]),
        'l\'Mgr Mande');
  });

  test('règle vide ignorée, caractères spéciaux échappés', () {
    expect(applyReplacements('a (b) c', const [Replacement(from: ' ', to: 'x')]), 'a (b) c');
    expect(applyReplacements('prix (CDF)', const [Replacement(from: '(CDF)', to: 'FC')]), 'prix FC');
  });

  test('segments : temps conservés', () {
    final out = applyReplacementsToSegments(
        const [Segment(startMs: 5, endMs: 9, text: 'mbote')],
        const [Replacement(from: 'mbote', to: 'Mbote')]);
    expect(out.single.startMs, 5);
    expect(out.single.text, 'Mbote');
  });

  test('stockage JSON, fichier abîmé ignoré', () {
    final tmp = Directory.systemTemp.createTempSync('andika_rep');
    final store = ReplacementStore('${tmp.path}/r.json');
    store.save(const [Replacement(from: 'a', to: 'b', matchCase: true)]);
    expect(store.load().single.matchCase, isTrue);
    File(store.path).writeAsStringSync('[{');
    expect(store.load(), isEmpty);
    tmp.deleteSync(recursive: true);
  });
}
