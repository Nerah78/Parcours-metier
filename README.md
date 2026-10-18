# Parcours

Addon pour **WoW Forever** (bêta, Interface 16001) : journal de progression des métiers (1 → 300) et suivi des marchands et professeurs favoris.

## Fonctions

- **Journal des métiers** : une page par métier appris (cuisine, alchimie, forge, ingénierie, couture, travail du cuir, enchantement, secourisme ; récolte en option), avec étapes, ingrédients, sources et maîtres.
- **Suivi de quêtes** à gauche de l'écran : un bloc par métier appris.
- **Marchands** : enregistre les composants et recettes vendus (tous métiers de production), favoris avec icône bourse sur la carte, la minimap et au-dessus du PNJ.
- **Professeurs favoris** : étoile dans la fenêtre du professeur, icône livre sur la carte, métier enseigné dans l'info-bulle.

## Installation

Copier le dépôt dans `World of Warcraft/_classic_/Interface/AddOns/Parcours` (le dossier doit s'appeler `Parcours`), puis `/reload` en jeu. Les dossiers `outils/` et `tests/` ne sont pas chargés par le jeu.

## Commandes

`/parcours` (journal), `/parcours metier NOM`, `/parcours recolte`, `/parcours suivi`, `/cmarch` (marchands, `/cmarch alchimie` pour filtrer), `/cmarch favoris`, `/cmarch professeur` (diagnostic).

## Données

`Donnees.lua` est généré depuis `outils/` :

```
python3 outils/generer_donnees.py outils/cuisine_wow_forever.xlsx Donnees.lua outils/metiers
```

## Licence

GPL v3 (voir `LICENSE`). Données issues de QuestieDB et AtlasLoot Classic : voir `CREDITS.txt`.
