# Jeu d'essai

Un jeu d'enregistrements de référence sert à mesurer la qualité et la vitesse (lot L10). Les fichiers audio ne sont pas dans le dépôt (confidentialité et poids) ; ils sont à réunir par Chadrack.

## Contenu à réunir (10 à 15 fichiers)

| N° | Type d'enregistrement | Durée conseillée | Langue |
| --- | --- | --- | --- |
| 1 | Interview calme, une personne, bon micro | 5 min | Français |
| 2 | Interview en extérieur, bruit de fond | 5 min | Français |
| 3 | Réunion avec plusieurs voix | 15 min | Français |
| 4 | Émission radio (voix et musique) | 10 min | Français |
| 5 | Appel téléphonique | 5 min | Français |
| 6 | Accent marqué ou débit rapide | 5 min | Français |
| 7 | Long enregistrement | 60 min | Français |
| 8 | Court enregistrement | 1 min | Français |
| 9 | Interview | 5 min | Anglais |
| 10 | Extrait parlé | 5 min | Swahili |
| 11 | Vidéo (MP4) avec piste audio | 5 min | Français |
| 12 | Fichier MP3, M4A, OGG ou OPUS (message vocal) | 2 min | Français |

## Texte de référence

Pour chaque fichier utilisé dans la mesure de qualité, écrire à la main le texte exact dans un fichier `.txt` (au moins 3 minutes d'audio par fichier). Ensuite :

```bash
python3 tools/wer.py reference.txt transcription.txt
```

Le script affiche le taux d'erreurs sur les mots (WER). Il ignore les majuscules et la ponctuation. Le seuil d'acceptation est à fixer après les premiers essais (critère C6 du plan de lots).

## Où noter les mesures

Dans `docs/MESURES.md` : appareil, RAM, version d'Android, modèle, durée de l'audio, durée du traitement, WER.
