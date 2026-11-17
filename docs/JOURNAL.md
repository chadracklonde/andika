# Journal de développement — Andika

Dernière mise à jour : voir l'historique Git. Ce fichier dit, lot par lot, ce qui est fait, **ce qui a été vérifié** et **ce qui ne l'a pas été**.

## Ce que l'environnement de développement autonome permettait

| Outil | Disponible | Conséquence |
| --- | --- | --- |
| Flutter / Dart | Non (téléchargement bloqué) | Le code Dart n'a pas été compilé ni exécuté. Il a été relu et contrôlé par un analyseur de syntaxe seulement. |
| Android SDK / Gradle Android | Non | Le code Kotlin et la configuration Gradle n'ont pas été compilés. Aucun APK n'a été construit. |
| Compilateur C++ et CMake | Oui | La couche native a été compilée et testée sur Linux avec whisper.cpp. |
| Modèles Whisper (Hugging Face) | Non (bloqué) | Aucune vraie transcription n'a été faite. Les tests natifs utilisent le petit modèle factice du dépôt whisper.cpp. |
| Téléphone Android | Non | Aucune mesure de vitesse, de mémoire ni de batterie. |

**Première chose à faire à ton réveil :** lancer `flutter pub get && flutter analyze && flutter test`, puis `flutter build apk --debug --target-platform android-arm64` sur ton ordinateur, et noter les erreurs. Le CI de GitHub fait la même chose à chaque envoi.

## État des lots

| Lot | État | Détail |
| --- | --- | --- |
| L0 | Fait | Squelette Flutter sans dépendance externe, configuration Gradle/Android écrite à la main, CI GitHub, décisions (`DECISIONS.md`), jeu d'essai, outil de mesure `tools/wer.py` (testé). **Non vérifié :** la configuration Gradle n'a pas été exécutée. |
| L1 | Fait (partie native vérifiée) | whisper.cpp 1.9.5 en sous-module, couche C `andika_whisper`, liaison Dart FFI. **Vérifié :** compilation Linux et 28 contrôles passent (SHA-1 sur les vecteurs officiels, détection d'en-tête de modèle, annulation, paramètres invalides, chargement du petit modèle factice). **Non vérifié :** compilation Android (NDK), liaison Dart, vraie transcription, mesures de vitesse et de mémoire (L1.2 à L1.5 : il faut un téléphone et les modèles). |
