import 'package:flutter_test/flutter_test.dart';

import 'package:andika/models/model_catalog.dart';

void main() {
  test('identifiants uniques et modèle recommandé présent', () {
    final ids = kModelCatalog.map((m) => m.id).toSet();
    expect(ids.length, kModelCatalog.length);
    expect(modelById(kRecommendedModelId), isNotNull);
  });

  test('les SHA-1 connus ont 40 caractères hexadécimaux', () {
    final hex = RegExp(r'^[0-9a-f]{40}$');
    for (final m in kModelCatalog) {
      if (m.sha1 != null) expect(hex.hasMatch(m.sha1!), isTrue, reason: m.id);
    }
  });

  test('url et seuils cohérents', () {
    for (final m in kModelCatalog) {
      expect(m.url, '$kModelBaseUrl/${m.fileName}');
      expect(m.comfortRamBytes >= m.minRamBytes, isTrue, reason: m.id);
    }
  });

  test('adéquation selon la mémoire', () {
    final base = modelById('base')!;
    expect(modelFit(base, 0), ModelFit.good);
    expect(modelFit(base, 1000 * 1000 * 1000), ModelFit.tooHeavy);
    expect(modelFit(base, 2500 * 1000 * 1000), ModelFit.tight);
    expect(modelFit(base, 6000 * 1000 * 1000), ModelFit.good);
  });

  test('recommandation : tiny sur très petit téléphone, base sinon', () {
    expect(recommendedModel(1000 * 1000 * 1000).id, 'tiny');
    expect(recommendedModel(4000 * 1000 * 1000).id, 'base');
    expect(recommendedModel(0).id, 'base');
  });
}
