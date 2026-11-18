# Cahier des charges — Andika, application Android de transcription audio (Whisper)

Version 1.0 · 18 novembre 2026 · Auteur : Chadrack Londe

## 1. Contexte et objectifs

Les journalistes, chercheurs et communicateurs ont besoin de transformer rapidement des enregistrements (interviews, réunions, cours, émissions radio) en texte. Sur iPhone et Mac, l'application Aiko répond à ce besoin avec une transcription hors ligne basée sur Whisper. Il n'existe pas d'équivalent aussi simple sur Android.

**Objectif :** développer une application Android qui transcrit des fichiers audio et vidéo **hors ligne**, sur le téléphone, avec le modèle Whisper, en privilégiant le français.

**Objectifs mesurables de la V1 :**

- Transcrire un fichier audio en français avec une qualité utilisable, sans connexion Internet.
- Exporter le résultat en TXT et en SRT.
- Rester stable sur un téléphone Android milieu de gamme (pas de plantage sur un fichier d'une heure).

**Nom de l'application :** Andika (« écris » en swahili). Le nom, le logo et l'interface doivent être originaux et ne pas imiter Aiko ni une autre application.

## 2. Périmètre

**Dans la V1 :**

- Import d'un fichier audio ou vidéo depuis le stockage ou le partage Android.
- Transcription hors ligne avec whisper.cpp.
- Choix de la langue (français par défaut, détection automatique possible).
- Choix du modèle (taille) et téléchargement des modèles à la demande.
- Affichage, édition et recherche dans le texte.
- Export TXT, SRT et DOCX, partage, et « Enregistrer sous… » dans le dossier de son choix.
- Historique local des transcriptions.
- Enregistreur numérique (dictaphone) intégré, avec une bibliothèque d'enregistrements : écouter, renommer, transcrire, récupérer l'audio, supprimer.

**Hors V1 (versions suivantes) :**

- Transcription en direct pendant l'enregistrement (la V1 transcrit après l'enregistrement).
- Identification des locuteurs.
- Traduction du texte transcrit.
- Synchronisation dans le cloud et comptes utilisateurs.
- Versions iOS, Windows et Web.

## 3. Utilisateurs cibles

- Journalistes et correspondants (interviews, reportages, radio).
- Étudiants et enseignants (cours, conférences).
- Responsables de communication (réunions, ateliers, rapports).
- Utilisateurs avec une connexion Internet faible ou chère : le fonctionnement hors ligne est un argument central.

## 4. Exigences fonctionnelles

| Réf. | Fonction | Description | Priorité |
| --- | --- | --- | --- |
| F1 | Import de fichier | Sélection d'un fichier audio ou vidéo (MP3, M4A, WAV, OGG, OPUS, AAC, MP4, MKV) via le sélecteur Android ou le menu « Partager vers » | Haute |
| F2 | Conversion audio | Conversion automatique en WAV 16 kHz mono, format attendu par Whisper | Haute |
| F3 | Choix de la langue | Français par défaut ; liste des langues prises en charge par Whisper ; option « détection automatique » | Haute |
| F4 | Choix du modèle | Liste des modèles avec taille, vitesse et qualité indicatives ; téléchargement à la demande avec progression, reprise et suppression | Haute |
| F5 | Transcription | Traitement local avec whisper.cpp, avec progression en pourcentage, annulation et reprise | Haute |
| F6 | Traitement en arrière-plan | La transcription continue si l'écran s'éteint ou si l'utilisateur change d'application, avec notification de progression | Haute |
| F7 | Affichage du résultat | Texte découpé en segments horodatés ; lecture audio synchronisée avec le texte | Haute |
| F8 | Édition | Correction du texte directement dans l'application | Haute |
| F9 | Export | TXT (avec ou sans horodatage) et SRT ; copie dans le presse-papiers ; partage Android | Haute |
| F10 | Historique | Liste locale des transcriptions (titre, date, durée, langue, modèle), renommage et suppression | Haute |
| F11 | Recherche | Recherche dans une transcription et dans l'historique | Moyenne |
| F12 | Remplacement de mots | Dictionnaire personnel de corrections automatiques appliquées après la transcription (noms propres, sigles) | Moyenne |
| F13 | Suppression des silences | Option de retirer les silences avant la transcription pour gagner du temps | Moyenne |
| F14 | Export DOCX | Export du texte dans un document Word (titre, segments, horodatages facultatifs) | Moyenne |
| F15 | Enregistrement | Enregistrer directement depuis l'application (micro), en pause/reprise, avec indicateur de niveau, y compris écran éteint | Haute |
| F16 | Bibliothèque d'enregistrements | Liste des enregistrements stockés dans l'application (nom, date, durée, taille) ; écoute ; renommage ; suppression ; réparation d'un enregistrement interrompu | Haute |
| F17 | Transcrire un enregistrement | Lancer la transcription d'un enregistrement depuis la bibliothèque, avec les mêmes choix de langue et de modèle que pour un fichier importé | Haute |
| F18 | Récupérer l'audio | Partager un enregistrement ou le copier (« Enregistrer sous… ») vers un dossier choisi par l'utilisateur, au format WAV | Haute |
| F19 | Enregistrer sous… | Exporter la transcription (TXT, SRT, DOCX) vers un dossier choisi, en plus du partage | Moyenne |
| F20 | Export de l'audio d'une transcription | Depuis le résultat, partager ou enregistrer l'audio converti associé | Basse |
| F21 | Recherche dans toutes les transcriptions | Depuis l'accueil, chercher un mot, un nom ou un lieu (sans tenir compte des accents ni de la casse) dans les titres et les textes de toute la bibliothèque ; extraits avec le passage surligné ; un appui ouvre la transcription au bon endroit | Haute |
| F22 | Partage de plusieurs fichiers | « Partager vers Andika » avec plusieurs fichiers à la fois (sélection multiple dans WhatsApp ou le gestionnaire de fichiers) : réglages choisis une fois, fichiers transcrits à la suite | Haute |
| F23 | Repères pendant l'enregistrement | Un bouton drapeau pose un repère à l'instant présent ; les repères s'affichent sur l'onde, sont conservés avec l'enregistrement et permettent d'écouter à partir de chacun dans la bibliothèque | Moyenne |
| F24 | Suivi du passage lu | Pendant l'écoute d'une transcription, la liste défile avec le passage en cours | Basse |

## 5. Exigences non fonctionnelles

- **Hors ligne :** après le téléchargement d'un modèle, aucune fonction essentielle ne doit nécessiter Internet.
- **Confidentialité :** les fichiers audio et les textes restent sur l'appareil. Aucune donnée n'est envoyée à un serveur. Pas de publicité ni de suivi de l'utilisateur dans la V1.
- **Compatibilité :** Android 8.0 (API 26) ou plus récent, architecture ARM 64 bits (arm64-v8a) obligatoire. Version minimale à confirmer après les tests.
- **Performance :** l'interface reste fluide pendant la transcription. L'objectif de vitesse (par exemple, durée de traitement par rapport à la durée de l'audio) sera mesuré sur les appareils de test, puis fixé.
- **Stabilité :** pas de plantage par manque de mémoire. Le modèle proposé par défaut doit tenir dans la mémoire des appareils de 4 Go de RAM. Les modèles trop lourds sont déconseillés ou bloqués selon la RAM détectée.
- **Stockage :** les modèles sont téléchargés à part, pas inclus dans l'APK. L'application affiche l'espace utilisé et permet de supprimer chaque modèle. Les enregistrements sont stockés dans l'espace privé de l'application au format WAV 16 kHz mono (environ 115 Mo par heure) ; la bibliothèque affiche l'espace occupé et prévient quand l'espace libre devient faible.
- **Enregistrement :** l'autorisation du micro n'est demandée qu'au premier enregistrement. L'enregistrement continue écran éteint grâce à un service au premier plan de type micro avec notification visible. Un enregistrement interrompu (plantage, batterie vide) reste récupérable. Aucun enregistrement ne quitte l'appareil sans action de l'utilisateur.
- **Batterie :** avertir l'utilisateur que les longues transcriptions consomment de la batterie ; proposer de la lancer pendant la charge.
- **Langue de l'interface :** français d'abord, anglais ensuite.
- **Accessibilité :** textes redimensionnables, contrastes suffisants, compatibilité avec TalkBack.

## 6. Architecture technique

**Technologies proposées :**

- **Interface et logique :** Flutter (Dart), cohérent avec les autres applications de Chadrack.
- **Moteur de transcription :** whisper.cpp (licence MIT), compilé pour Android avec le NDK et appelé depuis Dart par FFI. Une alternative plus rapide à mettre en place est un paquet Flutter existant qui enveloppe whisper.cpp (à évaluer : maintenance, compatibilité, performances).
- **Décodage audio :** MediaExtractor et MediaCodec côté Android (Kotlin, via un canal de plateforme) pour produire du PCM 16 kHz mono sans dépendance lourde. FFmpeg en solution de secours, à condition que le paquet utilisé soit encore maintenu.
- **Traitement en arrière-plan :** Isolate Dart pour ne pas bloquer l'interface, et service Android au premier plan avec notification pour que le système ne tue pas le traitement. Le type de service est à choisir selon les règles Android en vigueur.
- **Enregistrement :** AudioRecord (Kotlin) à 16 kHz mono PCM 16 bits, écrit directement en WAV ; service au premier plan de type micro. Les enregistrements sont ensuite transcrits sans conversion.
- **Export :** TXT, SRT, DOCX (généré en Dart pur, sans dépendance) ; « Enregistrer sous… » via le sélecteur de documents d'Android (ACTION_CREATE_DOCUMENT), qui n'exige aucune autorisation de stockage.
- **Stockage local :** SQLite (par exemple avec la bibliothèque drift) pour l'historique, les segments et le dictionnaire de remplacements ; fichiers pour l'audio et les modèles.
- **Téléchargement des modèles :** depuis un hébergement public (Hugging Face pour les modèles au format ggml de whisper.cpp), avec vérification d'intégrité par somme de contrôle.

**Organisation du code :** séparer clairement (1) l'interface, (2) la logique métier, (3) l'accès au moteur Whisper derrière une interface Dart unique. Cela permet de changer de moteur plus tard sans réécrire l'application.

## 7. Modèles Whisper

Les tailles sont approximatives et à vérifier sur les fichiers réellement utilisés.

| Modèle | Taille approximative | Usage conseillé |
| --- | --- | --- |
| tiny | environ 75 Mo | Tests, appareils très limités ; qualité faible |
| base | environ 140 Mo | Modèle par défaut conseillé pour la V1 |
| small | environ 470 Mo | Meilleure qualité sur appareils avec 6 Go de RAM ou plus |
| medium | environ 1,5 Go | Très lent sur téléphone ; à réserver à la V2 si les tests le permettent |

Les versions quantifiées (par exemple q5 ou q8) réduisent la taille et la mémoire utilisée pour une perte de qualité souvent faible. La V1 proposera au minimum **base** et **small**, dans une version quantifiée si les tests la valident.

## 8. Flux de traitement

1. L'utilisateur choisit un fichier (ou le partage vers l'application).
2. L'application vérifie qu'un modèle est installé, sinon propose de le télécharger.
3. Le fichier est décodé et converti en PCM 16 kHz mono.
4. L'audio est découpé en morceaux (si possible aux silences) pour afficher une progression et limiter la mémoire utilisée.
5. Whisper transcrit chaque morceau ; les segments avec horodatage sont enregistrés au fur et à mesure.
6. Le résultat s'affiche et reste modifiable ; l'historique est mis à jour.
7. L'utilisateur exporte ou partage le texte.

**Variante enregistreur :** l'utilisateur ouvre l'enregistreur, enregistre (pause/reprise possibles), arrête ; le fichier WAV est ajouté à la bibliothèque. Depuis la bibliothèque, il peut écouter, renommer, récupérer l'audio, supprimer, ou lancer la transcription : le flux continue alors à l'étape 2 ci-dessus, sans décodage.

Si l'application est interrompue (appel, redémarrage), la transcription doit pouvoir reprendre à partir des segments déjà enregistrés.

## 9. Écrans principaux

- **Accueil / Historique :** liste des transcriptions, bouton « Nouvelle transcription », recherche.
- **Nouvelle transcription :** choix du fichier, de la langue et du modèle, bouton de lancement.
- **Progression :** pourcentage, durée écoulée, bouton d'annulation.
- **Résultat :** texte par segments, lecteur audio, édition, recherche, export (copier, partager, enregistrer sous… en TXT, SRT, DOCX ; audio).
- **Enregistreur :** bouton d'enregistrement, chronomètre, niveau sonore, pause/reprise, arrêt.
- **Enregistrements :** bibliothèque avec lecture, renommage, transcription, récupération de l'audio, suppression, espace occupé.
- **Modèles :** liste des modèles, téléchargement, suppression, espace utilisé.
- **Dictionnaire :** liste des remplacements automatiques (par exemple « lomami » remplacé par « Lomami »).
- **Réglages :** langue de l'interface, langue de transcription par défaut, options d'export, à propos et licences.

## 10. Langues et qualité

- **Français et anglais :** objectif principal ; qualité attendue bonne avec les modèles base et small sur des enregistrements propres.
- **Swahili et lingala :** pris en charge par Whisper, mais avec peu de données d'entraînement, donc une qualité nettement plus faible. Le kingwana, variante locale du swahili, risque d'être encore moins bien reconnu. L'application doit l'indiquer clairement à l'utilisateur.
- **Piste d'amélioration :** tester des modèles ajustés pour le swahili disponibles publiquement et vérifier s'ils peuvent être convertis au format de whisper.cpp. Leur qualité et leur licence restent à contrôler avant toute intégration.
- **Facteurs de qualité :** bruit de fond, voix qui se chevauchent, accents, mélange de langues. Conseils d'enregistrement à afficher dans l'application (micro proche, lieu calme).

## 11. Licences et aspects juridiques

- Whisper (OpenAI) et whisper.cpp sont sous licence MIT. Vérifier la licence de chaque modèle téléchargé et de chaque bibliothèque ajoutée, et afficher les mentions requises dans l'écran « À propos ».
- Ne pas reprendre le nom, le logo, les textes ni l'interface d'Aiko ou d'une autre application.
- Politique de confidentialité publique, à rédiger avant la publication sur Google Play (aucune donnée collectée dans la V1).
- Respect des règles de Google Play : autorisations minimales, déclaration des données, règles sur les services au premier plan.

## 12. Plan de développement

Les durées sont des estimations à ajuster selon la disponibilité et les résultats des tests.

| Phase | Contenu | Durée estimée |
| --- | --- | --- |
| 0. Préparation | Choix du paquet ou de l'intégration FFI, appareils de test, jeu d'enregistrements de référence | 1 semaine |
| 1. Preuve de faisabilité | Transcrire un fichier WAV en français avec whisper.cpp sur un vrai téléphone, mesurer vitesse et mémoire | 1 à 2 semaines |
| 2. Cœur de l'application | Import, conversion audio, téléchargement des modèles, transcription avec progression, service en arrière-plan | 3 à 4 semaines |
| 3. Résultat et export | Affichage par segments, lecteur synchronisé, édition, export TXT et SRT, historique | 2 à 3 semaines |
| 4. Fonctions complémentaires | Recherche, dictionnaire de remplacements, suppression des silences | 2 semaines |
| 5. Tests et publication | Tests sur plusieurs appareils, correction des bugs, politique de confidentialité, fiche Google Play, version bêta fermée | 2 à 3 semaines |

## 13. Tests et critères d'acceptation

**Jeu d'essai :** réunir 10 à 15 enregistrements variés (interview calme, réunion avec plusieurs voix, enregistrement radio, appel téléphonique, extrait en swahili), de 1 à 60 minutes.

**Critères d'acceptation de la V1 :**

- Un fichier de 60 minutes est transcrit en entier sans plantage sur au moins deux appareils de test, dont un milieu de gamme.
- La transcription continue écran éteint et reprend après une interruption.
- Le texte exporté en TXT et en SRT s'ouvre correctement dans un éditeur de texte et dans un lecteur vidéo ; le DOCX s'ouvre dans Word ou LibreOffice.
- Un enregistrement de 60 minutes écran éteint est complet, apparaît dans la bibliothèque, peut être transcrit et son audio récupéré hors de l'application.
- Un enregistrement interrompu brutalement est récupérable et lisible.
- Aucun accès réseau n'a lieu pendant la transcription (vérifié en mode avion).
- L'application reste utilisable (navigation fluide) pendant la transcription.
- Le taux d'erreurs sur le jeu d'essai en français est mesuré et jugé acceptable par l'équipe de test (seuil à fixer après les premiers essais).

## 14. Risques et réponses prévues

| Risque | Réponse prévue |
| --- | --- |
| Transcription trop lente sur téléphone milieu de gamme | Modèle base quantifié par défaut ; découpage de l'audio ; message d'estimation du temps |
| Manque de mémoire ou plantage | Détection de la RAM, blocage des modèles trop lourds, traitement par morceaux |
| Android arrête le traitement en arrière-plan | Service au premier plan avec notification, reprise après interruption |
| Mauvaise qualité en swahili et kingwana | Annoncer la limite ; tester des modèles ajustés ; permettre une correction facile et un dictionnaire |
| Paquet Flutter non maintenu | Isoler le moteur derrière une interface ; prévoir l'intégration FFI directe |
| Chauffe et consommation de batterie | Avertissement, conseil de brancher le téléphone, option de pause |
| Espace de stockage insuffisant | Afficher la taille avant téléchargement, permettre la suppression des modèles ; avertir avant et pendant l'enregistrement quand l'espace libre est faible |
| Enregistrement coupé par le système ou perte de données | Service au premier plan de type micro ; en-tête WAV réparable ; conseil de désactiver l'optimisation de batterie |
| Autorisation du micro refusée | Message clair, lien vers les réglages, l'import de fichiers reste disponible |

## 15. Questions ouvertes

- Modèle économique : gratuite, payante une fois, ou gratuite avec options payantes ?
- Quels téléphones Android serviront aux tests (RAM, version d'Android) ?
- Quelle part de l'usage visé concerne le swahili et le lingala par rapport au français ?
- L'application sera-t-elle publiée sur Google Play, ou seulement distribuée en APK ?
- Décidé : l'export DOCX et l'enregistreur intégré entrent dans la V1 (demande du 18 novembre 2026).
- Faut-il proposer plus tard un format compressé (AAC/M4A) pour les enregistrements longs, afin de réduire l'espace occupé ?
