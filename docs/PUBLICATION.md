# Publication : ce qui reste à faire par une personne

Rien ici ne peut être fait automatiquement : cela demande des comptes, un téléphone ou une
décision de l'auteur.

## Vérifications faites

- Licences des composants : listées dans `THIRD_PARTY_NOTICES.md` (à recontrôler après le
  premier build, voir la section « À contrôler »).
- Nom, logo et interface : aucune ressource d'Aiko n'est reprise. L'icône est un dessin
  vectoriel d'origine (`ic_launcher_andika.xml`). **Non vérifié visuellement.**

## Risque sur le nom « Andika »

Une recherche (novembre 2026) montre qu'un **jeu Android nommé « Andika »** existe (page
itch.io et fiche Google Play `com.OGD.Andika`). Les catégories sont différentes (jeu
d'action contre outil de transcription), ce qui limite le risque, mais ce n'est pas un avis
juridique. À faire : recherche sur le Play Store lui-même et la base de marques de l'OMPI
et de l'OAPI (Organisation africaine de la propriété intellectuelle), réservation du nom de
domaine et du nom de développeur ; prévoir un nom de secours (« Andika Transcription »).
Le nom du paquet Android actuel est `org.chadracklonde.andika`.

## Avant la bêta fermée

1. Compiler (voir `docs/RAPPORT_QUALITE.md`, section 6) et corriger.
2. Créer une clé de signature (`keytool`), la **sauvegarder hors du dépôt**, remplacer la
   signature de débogage dans `android/app/build.gradle.kts`.
3. Choisir la licence du dépôt (décision de l'auteur) et l'ajouter.
4. Indiquer le contact dans la politique de confidentialité et la publier en ligne.
5. Compte développeur Google Play (frais uniques) ; piste de test fermée ; la procédure de
   test obligatoire pour les nouveaux comptes personnels est à vérifier dans la console.

## Bêta fermée (L11.6)

Recruter quelques journalistes avec des téléphones variés (RAM 3, 4, 6 Go), leur faire passer
le jeu d'essai, collecter : plantages, durée par heure d'audio, qualité du français, du
swahili, remarques sur l'interface. Reporter les mesures dans `docs/MESURES.md`.

## Distribution par APK (alternative)

`flutter build apk --release --split-per-abi`, puis partage direct. Les utilisateurs doivent
autoriser les sources inconnues ; il n'y a pas de mise à jour automatique.
