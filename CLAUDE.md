# Parcours : contexte pour Claude Code

Addon **World of Warcraft** pour WoW Forever (bêta, build 70009, Interface 16001, client type Classic avec API C_Map / C_NamePlate / C_Timer). Auteur : Sébastien, designer UX/UI, joueur Horde, communique **en français** (UI de l'addon, messages, commentaires en français).

## Contenu

Dépôt git (github.com/Nerah78/Parcours-metier) organisé à plat : la racine du dépôt **est** le dossier de l'addon, directement dans `Interface/AddOns/Parcours` (comme SalleDuTemps). Le jeu ignore `outils/`, `tests/` et les fichiers non listés dans le `.toc`. Git n'est pas dans le PATH : utiliser celui de GitHub Desktop (`%LOCALAPPDATA%\GitHubDesktop\app-*\resources\app\git\cmd\git.exe`).

- `Parcours.toc` : version, SavedVariables (`ParcoursDB`, `CuisineParcoursDB`, `CuisineMarchandsDB`), ordre de chargement `Donnees.lua`, `Parcours.lua`, `Marchands.lua`.
- `Donnees.lua` : **généré**, ne pas éditer à la main (voir « Données »). Table globale `ParcoursData` (12 métiers).
- `Parcours.lua` : journal des métiers 1→300 (fenêtre à onglets verticaux à droite, kit UI natif), suivi de quêtes à gauche (un bloc par métier appris), icône minimap, commandes `/parcours` et `/cparcours`.
- `Marchands.lua` : module marchands. Scan des vendeurs (composants + recettes de tous les métiers de production), favoris (étoile dans la fenêtre du marchand et du professeur), icônes sur carte du monde / minimap / plaques de nom, commande `/cmarch`.
- `outils/` : `generer_donnees.py`, `cuisine_wow_forever.xlsx` (cuisine), `metiers/*.json` (autres métiers).
- `tests/` : tests hors jeu avec Lua simulé (voir « Tests »).

## Architecture à connaître

- **Parcours.lua** : `Utiliser(id)` fixe l'upvalue `D` (métier courant). Toute fonction qui lit `D` doit être appelée après `Utiliser`. `DBM()` = base par métier (`ParcoursDB.metiers[id]`). `MetiersAffiches()` masque les métiers de récolte (herboristerie, minage, dépeçage, pêche) sauf réglage (`/parcours recolte`, case dans le journal ; liste codée en dur `METIERS_RECOLTE`). `StatutRecette(q)` : aucune / apprise / achetee / maitre / vendeur / inconnue. Le suivi se rafraîchit via `suiviDirty` (événements) et un sondage de signature chaque seconde.
- **Noms localisés** : les données contiennent des noms anglais (la cuisine a des noms français). À l'exécution : `GetSpellInfo(sortId)`, `GetItemInfo(id)`, `GetSpellTexture`, `GetItemIcon`.
- **Interface Parcours → Marchands** : `ParcoursMarchandsAPI.DefinirRecettes(liste)` (global défini dans Marchands.lua). Parcours calcule les vendeurs de recettes à acheter (étape en cours de chaque métier affiché, statut `vendeur`) et Marchands affiche un parchemin ; le marqueur disparaît quand la recette est achetée ou apprise.
- **Favoris** (`CuisineMarchandsDB._favoris`) : marchands (clé = id PNJ ou nom, icône bourse `VendorGossipIcon`), professeurs (clé `prof:<id>`, `type = "prof"`, icône livre `TrainerGossipIcon`, champ `metier`), marqueurs de recettes (`type = "recette"`, non sauvegardés, icône `INV_Scroll_03`).
- `Marqueurs()` fusionne favoris et marqueurs de recettes pour la carte, la minimap et les plaques.

## Pièges déjà rencontrés

- **Lua : une fonction `local` doit être définie avant son premier usage** (sinon nil à l'appel). Cause d'un vrai bug déjà corrigé.
- Données Questie : espaces insécables (` `) à normaliser ; noms de zones français de Questie peu fiables.
- Les `GameTooltip`, templates de frames (`BasicFrameTemplateWithInset`, `InsetFrameTemplate`, `SpellBookSkillLineTabTemplate`, `UICheckButtonTemplate`) peuvent manquer : toujours prévoir un repli (`pcall`).
- Parcourir `ParcoursData` : le champ `recolte = true` marque les métiers de récolte.
- Le nom exact de la fenêtre des professeurs sur la bêta est inconnu : le code essaie `ClassTrainerFrame`, `ProfessionTrainerFrame`, `TrainerFrame` (diagnostic : `/cmarch professeur`).

## Données

```
python3 -I outils/generer_donnees.py outils/cuisine_wow_forever.xlsx Donnees.lua outils/metiers
```

Sources : QuestieDB (GPL v3) et AtlasLoot Classic (GPL v2). Voir `CREDITS.txt`. Licence de l'addon : GPL v3. Les positions de vendeurs/maîtres marquées `origine = "web"` sont « à confirmer en jeu ».

## Tests

Nécessitent `pip install lupa`. Lua 5.4, API WoW simulée.

```
python3 tests/test_marchands.py     # module Marchands : cartes, minimap, plaques, professeurs, recettes
python3 tests/test_integration.py   # Parcours + Marchands chargés ensemble
```

Dans `test_integration.py`, la ligne « ok 4 ko 1 » vient d'une attente périmée sur le nombre d'onglets, ce n'est pas une vraie régression. Les tests ne remplacent pas une vérification en jeu : toute détection dépendant du client réel (noms de fenêtres, info-bulles, classe d'objet des recettes) reste à confirmer sur la bêta.

## À vérifier en jeu (en attente)

- Icône au-dessus de la tête des marchands favoris (`/cmarch plaques`).
- Détection des recettes de tous les métiers (`/cmarch debug`, puis `/reload` et lire le fichier de données).
- Métier affiché dans l'info-bulle des professeurs favoris.
- Sources des quêtes 4 et 5 côté Horde, niveau orange des Dry Pork Ribs (110 ou 80), id de la fiole vide en alchimie.
- Coordonnées des maîtres des métiers hors cuisine (absentes des données).

## Conventions

- Messages joueur et commentaires en français.
- Ne jamais écrire l'adresse e-mail personnelle dans le dépôt ; les commits utilisent l'adresse noreply GitHub.
- Après chaque changement : lancer les deux tests, vérifier la syntaxe Lua, incrémenter `## Version` dans le `.toc` si on livre une version.
