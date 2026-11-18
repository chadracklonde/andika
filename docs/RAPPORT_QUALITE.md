# Rapport de qualité — état au lot L10

> Ce rapport dit **ce qui a été vérifié** et **ce qui ne l'a pas été**. Aucun critère
> d'acceptation de la V1 (C1 à C6) n'est validé : ils exigent un vrai téléphone et le
> jeu d'essai, que l'environnement de développement automatique n'avait pas.

## 1. Ce qui a été exécuté

| Contrôle | Résultat | Commande |
| --- | --- | --- |
| Couche native C++ (whisper.cpp, interface `andika_*`) compilée sur ordinateur, 28 vérifications : en-têtes de modèle, SHA-1, annulation et sa remise à zéro, erreurs, silence | 28 / 28 réussies | `cmake -S native_tests -B build && cmake --build build && build/test_andika` |
| Calcul du taux d'erreurs (WER) | réussi | `python3 tools/test_wer.py` |
| Syntaxe de tous les fichiers Dart et Kotlin (analyse tree-sitter) | 0 erreur sur 53 fichiers | `python3 tools/check_syntax.py lib test android tools` |
| Cohérence entre fichiers : imports Dart, méthodes du canal Dart ↔ Kotlin (dans les deux sens), classes et ressources du manifeste, clés de texte FR/EN | aucun problème | `python3 tools/check_consistency.py` |
| Algorithmes rejoués en Python : découpage aux silences, recherche sans accent | valeurs attendues des tests Dart ; 2 défauts trouvés et corrigés (L7) | voir JOURNAL.md |

## 2. Ce qui n'a PAS été exécuté

- Aucune compilation Dart, Kotlin ni Gradle : pas de SDK Flutter, Dart ni Android ici.
  `flutter analyze` n'a jamais tourné. **Des erreurs de type ou d'API sont probables** ;
  ce sont les premières à corriger (le CI les montrera).
- Aucun des tests Dart (`test/*.dart`, 11 fichiers) n'a été exécuté.
- Aucune transcription réelle : modèle Whisper non téléchargeable depuis l'environnement
  (Hugging Face bloqué). La couche native a été testée avec un modèle factice.
- Aucune mesure de vitesse, de mémoire, de chauffe ni de batterie (`docs/MESURES.md` est vide).
- Aucun affichage de l'interface, aucun test TalkBack.

## 3. Critères d'acceptation (cahier, section 13)

| # | Critère | État | Pour le valider |
| --- | --- | --- | --- |
| C1 | 60 min transcrites sans plantage sur 2 appareils dont un milieu de gamme | **Non vérifié** | Transcrire le jeu d'essai (JEU_D_ESSAI.md) ; noter durée, pic de mémoire (`MESURES.md`) |
| C2 | Continue écran éteint, reprend après interruption | **Non vérifié** (mécanisme écrit : service d'avant-plan, verrou processeur, journal reprenable) | Lancer 20 min, éteindre l'écran, forcer l'arrêt de l'application, rouvrir, « Reprendre » |
| C3 | TXT et SRT s'ouvrent dans un éditeur et un lecteur vidéo | **Non vérifié** (formats générés conformes sur le papier ; tests écrits non exécutés) | Exporter, ouvrir le SRT dans VLC ou MX Player avec la vidéo |
| C4 | Aucun accès réseau pendant la transcription | **Non vérifié** ; par construction, aucun code réseau hors `model_downloader.dart` | Mode avion, transcrire ; ou journal du pare-feu |
| C5 | Interface fluide pendant la transcription | **Non vérifié** (calcul dans un isolate séparé) | Naviguer, défiler pendant une transcription ; outil de performance Flutter |
| C6 | Taux d'erreurs mesuré sur le jeu d'essai en français | **Non mesuré** (`tools/wer.py` prêt) | Transcrire, corriger à la main une référence, `python3 tools/wer.py ref.txt hyp.txt` |

## 4. Risques (cahier, section 14) : réponse réellement en place

| Risque | Réponse prévue | Réponse en place | Écart |
| --- | --- | --- | --- |
| Lenteur sur milieu de gamme | Modèle base quantifié par défaut ; découpage ; estimation du temps | Découpage aux silences, option d'ignorer les silences, estimation du temps restant, modèle **base non quantifié** par défaut | Le défaut n'est pas quantifié (la somme de contrôle de la variante q5_1 n'est pas publiée) ; estimation du temps restant ajoutée (rythme observé, après 2 morceaux). Défaut non quantifié à revoir après mesures. |
| Mémoire / plantage | Détection de la RAM, blocage des modèles trop lourds, morceaux | Fait (seuils de RAM = valeurs de départ, **à mesurer**) | Seuils non calibrés |
| Arrêt en arrière-plan | Service d'avant-plan, reprise | Service dataSync + notification + journal reprenable ; reprise à la demande (bouton) | Pas de reprise automatique ; certains constructeurs tuent quand même l'application |
| Qualité swahili/kingwana | Annoncer la limite ; modèles ajustés ; correction facile ; dictionnaire | Avertissement, correction par segment, dictionnaire | Modèles ajustés non testés (piste L12) |
| Paquet Flutter non maintenu | Moteur isolé ; FFI directe | Aucune dépendance Dart externe ; FFI directe vers whisper.cpp | Aucun |
| Chauffe et batterie | Avertissement, conseil, **option de pause** | Avertissements et conseils ; arrêt puis reprise | Pas de bouton « pause » distinct |
| Stockage | Taille affichée, suppression des modèles | Fait ; suppression de l'audio de travail en plus ; contrôle d'espace avant import et téléchargement | Aucun |

## 5. Défauts connus ou à surveiller

1. Première compilation : attendre des erreurs de type, d'import ou d'API Flutter.
2. `DropdownButtonFormField.value` : obsolète selon la version de Flutter (avertissement ignoré).
3. « Appliquer le dictionnaire » efface les corrections manuelles du texte.
4. Variantes `q5_1` : vérifiées seulement par en-tête et taille, sans SHA-1.
5. Seuils de RAM, nombre de fils (moitié des cœurs, entre 2 et 4) : valeurs de départ.
6. Découpage en morceaux de 10 à 28 s : une phrase coupée entre deux morceaux peut être mal transcrite.
7. Whisper peut inventer du texte sur du bruit ou du silence (« hallucinations ») : seul un filtre de répétitions (3 segments identiques de suite ou plus) est appliqué ; les phrases inventées non répétées passent.
8. Un seul travail à la fois ; pas de file d'attente.

## 6. Ordre conseillé au premier jour sur machine avec SDK

1. `flutter pub get && flutter analyze` — corriger les erreurs.
2. `flutter test` — corriger ou ajuster les tests.
3. `flutter build apk --debug` — corriger Gradle/CMake (NDK, `GGML_*`, page 16 Ko).
4. Installer sur un téléphone, télécharger `tiny`, transcrire 1 minute.
5. Passer à `base`, jeu d'essai complet, remplir `MESURES.md`, valider C1 à C6.
