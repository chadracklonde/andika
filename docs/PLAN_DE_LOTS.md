# Plan de lots — Andika

Version 1.0 · 18 novembre 2026 · Découpage du développement décrit dans [CAHIER_DES_CHARGES.md](CAHIER_DES_CHARGES.md).

Chaque lot est livrable et testable seul. Les durées sont indicatives, certains lots se recoupent ; le total visé reste de 11 à 15 semaines, comme au cahier des charges (section 12).

## Vue d'ensemble

| Lot | Titre | Dépend de | Durée indicative |
| --- | --- | --- | --- |
| L0 | Préparation et décisions | — | 1 semaine |
| L1 | Preuve de faisabilité du moteur | L0 | 1 à 2 semaines |
| L2 | Import et conversion audio | L1 | 1 à 1,5 semaine |
| L3 | Gestion des modèles | L1 | 1 semaine |
| L4 | Transcription | L2, L3 | 1,5 à 2 semaines |
| L5 | Arrière-plan et batterie | L4 | 1 semaine |
| L6 | Résultat, édition et historique | L4 | 1,5 à 2 semaines |
| L7 | Export et recherche | L6 | 1 semaine |
| L8 | Fonctions complémentaires | L4, L6 | 1 à 2 semaines |
| L9 | Interface, accessibilité et langues | L6 (en continu) | 1,5 à 2 semaines |
| L10 | Tests et qualité | L4 à L9 (en continu) | 2 semaines en fin de projet |
| L11 | Légal et publication | L10 | 1 à 2 semaines |
| L12 | Enregistreur et bibliothèque d'enregistrements | L4, L6 | 1,5 à 2 semaines |
| L13 | Export élargi (DOCX, Enregistrer sous…, audio) | L7, L12 | 1 semaine |
| L13b | Recherche globale, partage multiple, repères | L7, L12 | 2 à 3 jours |
| L14 | Après la V1 | L11 | hors V1 |

## L0 — Préparation et décisions

**Objectif :** poser le socle du projet et lever les questions ouvertes.

- L0.1 Créer le projet Flutter dans le dépôt (structure : interface, logique métier, accès au moteur), licence du dépôt, README.
- L0.2 Mettre en place la vérification automatique (analyse du code, tests, compilation) sur GitHub.
- L0.3 Réunir les appareils de test et noter leur RAM et leur version d'Android (Q2).
- L0.4 Constituer le jeu d'essai de 10 à 15 enregistrements (section 13 du cahier) avec le texte de référence pour les mesures.
- L0.5 Choisir : paquet Flutter existant ou intégration FFI directe (section 6).
- L0.6 Décider : modèle économique (Q1), publication Google Play ou APK seul (Q4), part du swahili et du lingala (Q3), export DOCX dès la V1 ou non (Q5).

**Livrable :** projet qui compile, jeu d'essai, décisions notées.
**Fin du lot :** les cinq questions ouvertes ont une réponse écrite.

## L1 — Preuve de faisabilité du moteur

**Objectif :** prouver que whisper.cpp transcrit en français sur un vrai téléphone.

- L1.1 Compiler whisper.cpp pour arm64-v8a avec le NDK.
- L1.2 Transcrire un fichier WAV 16 kHz en français sur un téléphone, avec les modèles base et small.
- L1.3 Mesurer la vitesse (durée de traitement par rapport à la durée de l'audio), la mémoire utilisée et la chauffe, sur chaque appareil de test.
- L1.4 Tester les versions quantifiées (q5, q8) et décider lesquelles proposer.
- L1.5 Tester l'ajout de la détection automatique de langue et un extrait en swahili, pour fixer l'avertissement à afficher.
- L1.6 Définir l'interface Dart unique qui cache le moteur (section 6, organisation du code).

**Livrable :** rapport de mesures court, moteur appelable depuis Flutter.
**Fin du lot :** décision écrite sur le modèle par défaut et les seuils de RAM.

## L2 — Import et conversion audio

**Objectif :** transformer n'importe quel fichier accepté en audio utilisable par Whisper.

- L2.1 Sélecteur de fichiers et réception du menu « Partager vers » (F1).
- L2.2 Formats : MP3, M4A, WAV, OGG, OPUS, AAC, MP4, MKV (F1).
- L2.3 Décodage et conversion en PCM 16 kHz mono (F2).
- L2.4 Découpage en morceaux, si possible aux silences (section 8, étape 4).
- L2.5 Gestion des erreurs : fichier illisible, sans piste audio, trop volumineux, espace insuffisant.

**Livrable :** un fichier choisi devient une liste de morceaux prêts à transcrire.
**Fin du lot :** tous les formats listés passent sur le jeu d'essai.

## L3 — Gestion des modèles

**Objectif :** télécharger, vérifier et supprimer les modèles sans les inclure dans l'APK.

- L3.1 Écran « Modèles » : liste, taille, vitesse et qualité indicatives (F4).
- L3.2 Téléchargement avec progression, pause, reprise après coupure de réseau (F4).
- L3.3 Vérification de l'intégrité par somme de contrôle (section 6).
- L3.4 Suppression d'un modèle et affichage de l'espace utilisé (F4, exigence Stockage).
- L3.5 Détection de la RAM : modèles trop lourds déconseillés ou bloqués (exigence Stabilité).
- L3.6 Contrôle de l'espace libre avant téléchargement.

**Livrable :** modèles base et small installables et supprimables.
**Fin du lot :** téléchargement repris après une coupure, somme de contrôle vérifiée.

## L4 — Transcription

**Objectif :** transcrire un fichier du début à la fin, avec progression.

- L4.1 Choix de la langue : français par défaut, liste complète, détection automatique (F3).
- L4.2 Choix du modèle avant le lancement (F4, F5).
- L4.3 Exécution dans un Isolate, interface toujours fluide (F5, exigence Performance).
- L4.4 Progression en pourcentage et durée écoulée (F5).
- L4.5 Annulation et reprise à partir des segments déjà enregistrés (F5, section 8).
- L4.6 Enregistrement des segments horodatés au fur et à mesure.
- L4.7 Traitement par morceaux pour éviter les manques de mémoire (exigence Stabilité).
- L4.8 Aucun accès réseau pendant la transcription (exigences Hors ligne et Confidentialité).

**Livrable :** transcription complète d'un fichier avec segments horodatés.
**Fin du lot :** un fichier de 60 minutes est transcrit en entier sur un appareil de test.

## L5 — Arrière-plan et batterie

**Objectif :** que la transcription survive à l'écran éteint et aux interruptions.

- L5.1 Service Android au premier plan avec notification de progression (F6).
- L5.2 Choix du type de service selon les règles Android en vigueur (section 6).
- L5.3 Reprise après interruption : appel, fermeture de l'application, redémarrage (section 8).
- L5.4 Avertissement sur la consommation de batterie et conseil de brancher le téléphone ; option de pause (exigence Batterie).
- L5.5 Gestion des restrictions d'économie d'énergie des fabricants.

**Livrable :** transcription qui continue écran éteint.
**Fin du lot :** critère d'acceptation « écran éteint et reprise » validé.

## L6 — Résultat, édition et historique

**Objectif :** afficher, corriger et conserver les transcriptions.

- L6.1 Base de données locale : transcriptions, segments, dictionnaire (section 6).
- L6.2 Affichage par segments horodatés (F7).
- L6.3 Lecteur audio synchronisé avec le texte (F7).
- L6.4 Édition du texte dans l'application (F8).
- L6.5 Historique : titre, date, durée, langue, modèle ; renommage et suppression (F10).
- L6.6 Suppression des fichiers audio copiés quand une transcription est supprimée.

**Livrable :** écran « Résultat » et écran « Historique ».
**Fin du lot :** une transcription corrigée est retrouvée intacte après redémarrage.

## L7 — Export et recherche

**Objectif :** sortir le texte de l'application et le retrouver.

- L7.1 Export TXT avec ou sans horodatage (F9).
- L7.2 Export SRT (F9).
- L7.3 Copie dans le presse-papiers et partage Android (F9).
- L7.4 Recherche dans une transcription (F11).
- L7.5 Recherche dans l'historique (F11).

**Livrable :** exports valides, recherche fonctionnelle.
**Fin du lot :** le SRT s'ouvre dans un lecteur vidéo et le TXT dans un éditeur de texte.

## L8 — Fonctions complémentaires

**Objectif :** gagner du temps et de la qualité.

- L8.1 Dictionnaire de remplacements automatiques, par exemple « lomami » en « Lomami » (F12).
- L8.2 Écran « Dictionnaire » : ajout, modification, suppression (F12).
- L8.3 Option de suppression des silences avant la transcription (F13).
- L8.4 Conseils d'enregistrement affichés dans l'application (section 10).

**Livrable :** corrections automatiques et option de suppression des silences.
**Fin du lot :** le dictionnaire s'applique à une transcription du jeu d'essai.

## L9 — Interface, accessibilité et langues

**Objectif :** une application complète, claire et accessible.

- L9.1 Accueil et historique (section 9).
- L9.2 Écran « Nouvelle transcription » (section 9).
- L9.3 Écran « Progression » (section 9).
- L9.4 Écran « Réglages » : langue de l'interface, langue de transcription par défaut, options d'export (section 9).
- L9.5 Écran « À propos » avec les mentions de licences (section 11).
- L9.6 Interface en français puis en anglais (exigence Langue de l'interface).
- L9.7 Textes redimensionnables, contrastes, compatibilité avec TalkBack (exigence Accessibilité).
- L9.8 Message clair sur la qualité limitée en swahili, en lingala et en kingwana (section 10).

**Livrable :** application complète de bout en bout.
**Fin du lot :** parcours complet réalisable sans aide, avec TalkBack activé.

## L10 — Tests et qualité

**Objectif :** vérifier chaque critère d'acceptation sur de vrais appareils.

- L10.1 Mesurer le taux d'erreurs sur le jeu d'essai en français et fixer le seuil jugé acceptable (C6).
- L10.2 Transcrire 60 minutes sur au moins deux appareils dont un milieu de gamme (C1).
- L10.3 Vérifier l'écran éteint et la reprise après interruption (C2).
- L10.4 Vérifier les exports TXT et SRT (C3).
- L10.5 Vérifier l'absence d'accès réseau en mode avion (C4).
- L10.6 Vérifier la fluidité pendant la transcription (C5).
- L10.7 Mesurer la vitesse finale et fixer l'objectif de performance (exigence Performance).
- L10.8 Vérifier la compatibilité : Android 8.0 minimum, arm64-v8a (exigence Compatibilité).
- L10.9 Passer en revue chaque risque du cahier et noter la réponse mise en place (R1 à R7).
- L10.10 Tests automatiques sur la logique métier (conversion, découpage, export SRT, dictionnaire).

**Livrable :** rapport de tests, liste des défauts corrigés.
**Fin du lot :** les critères C1 à C6 sont validés.

## L11 — Légal et publication

**Objectif :** publier sans mauvaise surprise.

- L11.1 Contrôler la licence de chaque bibliothèque et de chaque modèle, afficher les mentions (section 11).
- L11.2 Rédiger la politique de confidentialité publique (section 11).
- L11.3 Préparer la fiche Google Play : titre, description, captures d'écran, déclaration des données, autorisations minimales (section 11).
- L11.4 Vérifier le nom, le logo et l'interface : rien d'imité d'Aiko (section 11).
- L11.5 Vérifier que le nom Andika est libre sur Google Play, GitHub et en nom de domaine, et le risque de marque.
- L11.6 Version bêta fermée avec quelques journalistes, collecte des retours.
- L11.7 Publication, ou distribution en APK selon la décision de L0.6.

**Livrable :** version 1.0 publiée ou diffusée.
**Fin du lot :** bêta sans plantage bloquant, fiche acceptée.

## L12 — Enregistreur et bibliothèque d'enregistrements

**Objectif :** enregistrer depuis l'application, conserver les enregistrements, les transcrire et récupérer l'audio (F15 à F18).

- L12.1 Enregistreur Kotlin (AudioRecord 16 kHz mono PCM 16 bits, écriture WAV directe), pause/reprise, niveau sonore.
- L12.2 Service au premier plan de type micro ; autorisations RECORD_AUDIO (à l'exécution) et FOREGROUND_SERVICE_MICROPHONE.
- L12.3 Stockage des enregistrements et réparation d'en-tête WAV après interruption.
- L12.4 Écrans Enregistreur et Enregistrements (lecture, renommage, suppression, espace occupé).
- L12.5 Transcrire depuis la bibliothèque (réutilise le flux L4 sans décodage).
- L12.6 Textes FR/EN, accessibilité, tests.

**Fin du lot :** un enregistrement écran éteint apparaît dans la bibliothèque, se transcrit et se récupère.

## L13 — Export élargi

**Objectif :** exporter le texte et l'audio où l'utilisateur le souhaite (F14, F19, F20, F18).

- L13.1 Générateur DOCX en Dart pur (archive ZIP sans compression, CRC32), tests de structure.
- L13.2 « Enregistrer sous… » (sélecteur de documents Android) pour TXT, SRT, DOCX et WAV.
- L13.3 Menu d'export du résultat et de la bibliothèque mis à jour.
- L13.4 Textes FR/EN, tests.

**Fin du lot :** le DOCX s'ouvre dans Word ou LibreOffice ; les fichiers enregistrés sous… sont lisibles.

## L13b — Recherche globale, partage multiple, repères

**Objectif :** F21 à F24.

- L13b.1 Recherche dans l'historique (`searchHistory`, écran de recherche, ouverture au bon passage).
- L13b.2 Intent `SEND_MULTIPLE`, liste de fichiers du côté Kotlin et Dart, mise à la suite avec les mêmes réglages.
- L13b.3 Repères : bouton, drapeaux sur l'onde, stockage dans la fiche, puces d'écoute dans la bibliothèque.
- L13b.4 Défilement de la liste avec la lecture, textes FR/EN, tests.

**Fin du lot :** une recherche retrouve un nom dans plusieurs transcriptions ; trois vocaux partagés depuis WhatsApp sont transcrits à la suite ; un repère posé à l'enregistrement permet d'écouter à partir de là.

## L14 — Après la V1

Hors périmètre de la V1, à planifier ensuite :

- Transcription en direct, identification des locuteurs, traduction, synchronisation cloud, versions iOS, Windows et Web (section 2).
- Enregistrement compressé (AAC/M4A).
- Modèle medium, modèles ajustés pour le swahili (sections 7 et 10).

## Matrice de traçabilité

Chaque exigence du cahier des charges est rattachée à au moins un lot.

| Exigence | Lot(s) |
| --- | --- |
| F1 Import de fichier | L2 |
| F2 Conversion audio | L2 |
| F3 Choix de la langue | L4 |
| F4 Choix du modèle | L3, L4 |
| F5 Transcription | L4 |
| F6 Traitement en arrière-plan | L5 |
| F7 Affichage du résultat | L6 |
| F8 Édition | L6 |
| F9 Export | L7 |
| F10 Historique | L6 |
| F11 Recherche | L7 |
| F12 Remplacement de mots | L8 |
| F13 Suppression des silences | L8 |
| F14 Export DOCX | L13 |
| F15 Enregistrement | L12 |
| F16 Bibliothèque d'enregistrements | L12 |
| F17 Transcrire un enregistrement | L12 |
| F18 Récupérer l'audio | L12, L13 |
| F19 Enregistrer sous… | L13 |
| F20 Export de l'audio d'une transcription | L13 |
| F21 à F24 Recherche globale, partage multiple, repères, suivi du passage | L13b |
| Hors ligne | L3, L4 |
| Confidentialité | L4, L11 |
| Compatibilité | L1, L10 |
| Performance | L1, L4, L10 |
| Stabilité | L3, L4 |
| Stockage | L3 |
| Batterie | L5 |
| Langue de l'interface | L9 |
| Accessibilité | L9 |
| Section 10 — Langues et qualité | L1, L8, L9 |
| Section 11 — Licences et aspects juridiques | L9, L11 |
| Critères d'acceptation C1 à C6 et critères enregistreur | L10, L12, L13 |
| Risques R1 à R7 | L0 (R5), L1 (R1, R4, R5), L3 (R2, R7), L4 (R1, R2), L5 (R3, R6), L8 et L9 (R4), L10 (tous) |
| Questions ouvertes Q1 à Q5 | L0 |

**Critères d'acceptation (section 13) :**

- C1 : fichier de 60 minutes transcrit en entier sur deux appareils.
- C2 : transcription qui continue écran éteint et reprend après interruption.
- C3 : exports TXT et SRT valides.
- C4 : aucun accès réseau pendant la transcription.
- C5 : application fluide pendant la transcription.
- C6 : taux d'erreurs mesuré et jugé acceptable en français.

**Risques (section 14) :**

- R1 : transcription trop lente.
- R2 : manque de mémoire ou plantage.
- R3 : arrêt du traitement en arrière-plan par Android.
- R4 : mauvaise qualité en swahili et kingwana.
- R5 : paquet Flutter non maintenu.
- R6 : chauffe et consommation de batterie.
- R7 : espace de stockage insuffisant.

**Questions ouvertes (section 15) :**

- Q1 : modèle économique.
- Q2 : téléphones de test.
- Q3 : part du swahili et du lingala.
- Q4 : Google Play ou APK seul.
- Q5 : export DOCX dès la V1.
