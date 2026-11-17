# Andika

Application Android qui transcrit des fichiers audio et vidéo **hors ligne**, sur le téléphone, avec Whisper. Les fichiers et les textes ne quittent jamais l'appareil.

> État : développement en cours. Voir [docs/JOURNAL.md](docs/JOURNAL.md) pour l'avancement et ce qui reste à vérifier.

## Documents

- [Cahier des charges](docs/CAHIER_DES_CHARGES.md)
- [Plan de lots](docs/PLAN_DE_LOTS.md)
- [Décisions prises en autonomie](docs/DECISIONS.md)
- [Journal de développement](docs/JOURNAL.md)

## Construire l'application

Prérequis : Flutter (version stable récente), Android SDK avec NDK et CMake, Java 17.

```bash
git clone --recurse-submodules https://github.com/chadracklonde/andika
cd andika
flutter pub get
flutter run                     # sur un téléphone ou un émulateur
flutter build apk --release --target-platform android-arm64
```

Si le dépôt a été cloné sans `--recurse-submodules` : `git submodule update --init --recursive`.

## Utilisation

1. Ouvrir Andika, puis télécharger un modèle (écran « Modèles »). Le modèle `base` est un bon point de départ.
2. Choisir un fichier audio ou vidéo, ou le partager vers Andika depuis une autre application.
3. Choisir la langue et lancer la transcription. Elle continue écran éteint.
4. Corriger le texte si besoin, puis l'exporter en TXT ou en SRT.

## Structure

```
lib/                        code Flutter (interface et logique)
android/app/src/main/kotlin code Android natif (audio, service, partage)
android/app/src/main/cpp    couche C++ entre Flutter et whisper.cpp
third_party/whisper.cpp     moteur de transcription (sous-module Git)
tools/                      outils (calcul du taux d'erreurs)
docs/                       cahier des charges, plan, décisions, journal
```

## Licences

Voir [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) pour les composants tiers (Whisper, whisper.cpp).
