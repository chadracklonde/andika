# Décisions prises en autonomie (lot L0)

Ces décisions ont été prises pendant le développement autonome de la nuit du 17 au 18 novembre 2026, sans validation préalable. Chacune est modifiable. Les questions ouvertes du cahier des charges (section 15) y sont traitées en premier.

## Réponses provisoires aux questions ouvertes

| Question | Décision provisoire | Pourquoi |
| --- | --- | --- |
| Q1 Modèle économique | V1 gratuite, sans publicité, sans compte | Cohérent avec l'argument « tout reste sur le téléphone » ; on pourra ajouter une option payante plus tard |
| Q2 Téléphones de test | Non connus : à renseigner dans `docs/MESURES.md` | Je n'ai pas accès à un téléphone ; les seuils de RAM du code sont des valeurs de départ prudentes |
| Q3 Swahili et lingala | Français et anglais d'abord ; swahili et lingala proposés avec un avertissement de qualité | Whisper est faible sur ces langues, voir la section 10 du cahier |
| Q4 Distribution | APK en bêta fermée d'abord, Google Play ensuite | Permet de tester sur de vrais téléphones avant de publier |
| Q5 Export Word (DOCX) | Hors V1 (lot L12) | Le TXT et le SRT suffisent pour la V1 ; le texte se copie facilement dans Word |

## Choix techniques

- **Aucune dépendance Dart externe.** Le fichier `pubspec.yaml` ne contient que Flutter. Je n'ai pas pu vérifier les versions des paquets ni leurs interfaces (pub.dev inaccessible depuis mon environnement), et un paquet qui change d'interface casserait la compilation. Les fonctions Android passent par du code Kotlin écrit pour ce projet.
- **Stockage en fichiers JSON** (historique, segments, dictionnaire) à la place de SQLite/drift. Le volume est faible, et cela évite un paquet. On pourra migrer vers SQLite si l'historique devient très grand.
- **Moteur :** whisper.cpp version 1.9.5, ajouté comme sous-module Git (`third_party/whisper.cpp`), compilé par CMake avec le NDK et appelé par `dart:ffi` via une petite couche C (`android/app/src/main/cpp/andika_whisper.cpp`).
- **Modèle par défaut : `base` non quantifié** (142 Mo environ). Sa somme de contrôle SHA-1 est publiée par le projet whisper.cpp, donc le téléchargement est vérifiable. Les versions quantifiées q5_1 sont proposées comme options plus légères, mais leur somme de contrôle n'est pas publiée : elles sont seulement contrôlées par leur en-tête et leur taille.
- **Audio :** décodage par `MediaExtractor` et `MediaCodec` en Kotlin, vers un fichier WAV 16 kHz mono conservé dans l'application (il sert aussi à la lecture synchronisée).
- **Service au premier plan :** type `dataSync`.
- **Plateformes :** ARM 64 bits (`arm64-v8a`) pour les téléphones et `x86_64` pour l'émulateur. Android 8.0 (API 26) minimum.
- **Identifiant de l'application :** `org.chadracklonde.andika`.
- **Licence du dépôt :** non choisie ; c'est à Chadrack de la décider (le choix engage l'auteur). Les licences des composants tiers sont dans `THIRD_PARTY_NOTICES.md`.
