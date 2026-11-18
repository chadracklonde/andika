# Composants tiers

Andika utilise les composants suivants. Les textes complets des licences sont dans les
dépôts d'origine et, pour whisper.cpp, dans `third_party/whisper.cpp/LICENSE`.

| Composant | Rôle | Licence | Source |
| --- | --- | --- | --- |
| whisper.cpp (v1.9.5) et ggml | Moteur de transcription, compilé dans l'application | MIT, Copyright (c) 2023-2026 The ggml authors | https://github.com/ggml-org/whisper.cpp |
| Modèles Whisper (poids au format ggml) | Reconnaissance de la parole, **téléchargés par l'utilisateur** et non inclus dans l'application | MIT, OpenAI | https://github.com/openai/whisper ; fichiers ggml : https://huggingface.co/ggerganov/whisper.cpp |
| Flutter et Dart | Interface | BSD 3-clauses, The Flutter Authors / The Dart Authors | https://flutter.dev |
| AndroidX (`androidx.core`, dont FileProvider) | Partage de fichiers | Apache 2.0, The Android Open Source Project | https://developer.android.com/jetpack/androidx |
| Kotlin (bibliothèque standard) | Code Android | Apache 2.0, JetBrains | https://kotlinlang.org |

## À contrôler avant publication

- Les variantes quantifiées (`q5_1`) sont des conversions des modèles OpenAI publiées sur
  Hugging Face : vérifier que la fiche du dépôt indique bien la licence MIT.
- Les licences des dépendances Gradle transitives (Flutter embedding) sont affichées dans
  l'écran « Licences des composants » de l'application (`showLicensePage`) ; contrôler après
  le premier build que whisper.cpp y figure, sinon l'ajouter par `LicenseRegistry.addLicense`.
- Toute licence de l'application Andika elle-même reste à choisir par l'auteur.

## Mention d'indépendance

Andika est une application indépendante. Elle s'inspire de l'idée d'Aiko (Sindre Sorhus)
sur iPhone, mais n'en reprend ni le code, ni le nom, ni le logo, ni l'apparence.
