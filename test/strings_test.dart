import 'package:flutter_test/flutter_test.dart';

import 'package:andika/app/strings.dart';

void main() {
  test('français et anglais ont les mêmes clés', () {
    expect(kStringsFr.keys.toSet(), kStringsEn.keys.toSet());
  });

  test('mêmes paramètres dans les deux langues', () {
    final re = RegExp(r'\{(\w+)\}');
    for (final key in kStringsFr.keys) {
      final fr = re.allMatches(kStringsFr[key]!).map((m) => m.group(1)).toSet();
      final en = re.allMatches(kStringsEn[key]!).map((m) => m.group(1)).toSet();
      expect(fr, en, reason: key);
    }
  });

  test('remplacement des paramètres et clé inconnue', () {
    final s = Strings.forCode('fr');
    expect(s.t('notif_progress', {'n': '42'}), '42 % terminé');
    expect(Strings.forCode('en').t('notif_progress', {'n': '42'}), '42% done');
    expect(s.t('inexistante'), 'inexistante');
    expect(s.has('cancel'), isTrue);
  });

  test('toute erreur de modèle ou d\'import connue a un texte', () {
    for (final code in ['network', 'http', 'no_space', 'incomplete', 'invalid', 'checksum', 'io']) {
      expect(kStringsFr.containsKey('err_model_$code'), isTrue, reason: code);
    }
    for (final code in ['no_space', 'no_audio', 'unsupported', 'read_error', 'decode_error', 'cancelled']) {
      expect(kStringsFr.containsKey('err_import_$code'), isTrue, reason: code);
    }
  });
}
