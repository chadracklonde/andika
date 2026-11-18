import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:andika/app/settings.dart';

void main() {
  test('fils de calcul bornés entre 2 et 4', () {
    expect(defaultThreads(2), 2);
    expect(defaultThreads(4), 2);
    expect(defaultThreads(6), 3);
    expect(defaultThreads(8), 4);
    expect(defaultThreads(16), 4);
  });

  test('langues à qualité limitée', () {
    expect(isLimitedQuality('sw'), isTrue);
    expect(isLimitedQuality('ln'), isTrue);
    expect(isLimitedQuality('fr'), isFalse);
    expect(isLimitedQuality('zz'), isFalse);
  });

  test('réglages : aller-retour et fichier abîmé', () {
    final tmp = Directory.systemTemp.createTempSync('andika_set');
    final store = SettingsStore('${tmp.path}/s.json');
    expect(store.load().modelId, 'base');
    store.save(const Settings(uiLanguage: 'en', skipSilence: true, modelId: 'small'));
    final back = store.load();
    expect(back.uiLanguage, 'en');
    expect(back.skipSilence, isTrue);
    expect(back.modelId, 'small');
    File(store.path).writeAsStringSync('{');
    expect(store.load().uiLanguage, 'system');
    tmp.deleteSync(recursive: true);
  });
}
