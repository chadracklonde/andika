# Fiche Google Play (brouillon)

## Titre (30 caractères maximum)

Andika : transcription audio

## Description courte (80 caractères maximum)

Transcrivez audio et vidéo en texte sur votre téléphone, sans Internet.

## Description longue

Andika transforme vos enregistrements en texte directement sur votre téléphone, grâce au
modèle de reconnaissance vocale Whisper. Vos fichiers ne quittent jamais l'appareil.

• Interviews, réunions, émissions, messages vocaux : choisissez un fichier audio ou vidéo, ou
  partagez-le vers Andika depuis une autre application.
• Fonctionne sans Internet, après le téléchargement d'un modèle (une seule fois).
• Continue en arrière-plan et écran éteint ; reprend là où il s'est arrêté après une
  interruption.
• Réécoutez l'enregistrement : le texte se surligne au fil de la lecture, touchez une phrase
  pour y aller, corrigez-la du doigt.
• Recherche dans le texte, copie, partage en TXT ou en sous-titres SRT.
• Dictionnaire de remplacement pour les noms propres et les termes locaux.
• Choix du modèle selon la puissance de votre téléphone (rapide ou plus précis).
• En français et en anglais. Pas de compte, pas de publicité.

Langues : Whisper reconnaît une centaine de langues. Le français et l'anglais donnent les
meilleurs résultats. Le swahili et le lingala sont moins bien reconnus : prévoyez de corriger
le texte.

Andika est une application indépendante, qui n'est affiliée ni à OpenAI ni à Aiko.

## Catégorie

Productivité (ou Outils).

## Section « Sécurité des données » (à déclarer)

- Données collectées : aucune.
- Données partagées : aucune.
- Données chiffrées en transit : sans objet (le téléchargement des modèles se fait en HTTPS).
- Suppression des données : par l'utilisateur dans l'application, ou en désinstallant.
- Politique de confidentialité : à publier à une adresse publique (par exemple GitHub Pages)
  à partir de `docs/POLITIQUE_DE_CONFIDENTIALITE.md`.

## Autorisations et justifications

| Autorisation | Justification à fournir |
| --- | --- |
| INTERNET | Télécharger les modèles à la demande de l'utilisateur |
| POST_NOTIFICATIONS | Notification de progression pendant une transcription |
| FOREGROUND_SERVICE + FOREGROUND_SERVICE_DATA_SYNC | Transcription longue lancée par l'utilisateur ; la déclaration « type de service d'avant-plan » de Play Console demande une courte vidéo de démonstration |
| WAKE_LOCK | Garder le processeur actif écran éteint pendant la transcription |

## Captures d'écran à prévoir (au moins 2, idéalement 4 à 8)

1. Historique. 2. Nouvelle transcription (langue, modèle). 3. Progression. 4. Résultat avec
lecture. 5. Modèles. À réaliser sur un vrai téléphone une fois l'application compilée.

## Cible de l'API

La cible actuelle de Google Play et la version `targetSdk` de `build.gradle.kts` doivent être
vérifiées au moment de la publication (les exigences changent chaque année).
