# CLAUDE.md — Photo Roulette

## Projet
Jeu de soirée « à qui est cette photo ? ». Flutter (Android + web), Supabase. Repo `foclabroc/photo_roulette`, branche `main`.

## Choix figés
- Stack : Flutter + Supabase (auth anonyme, Realtime, Storage).
- Multijoueur : salon en ligne avec code à 5 caractères (sans 0/O/1/I/L), 2 à 12 joueurs.
- Photos : tirage au hasard + droit de veto avant envoi. Sur web, le navigateur ne peut pas lire la galerie : sélection manuelle d'un lot, tirage dans ce lot.
- Plateformes : Android + web (GitHub Pages).
- Tout est préfixé `pr_` côté base (tables, fonctions) ; bucket privé `pr-photos`, chemin `<room_id>/<player_id>/<fichier>.jpg`.

## Structure
- `lib/config.dart` : config via `--dart-define` (SUPABASE_URL, SUPABASE_ANON_KEY).
- `lib/models/room.dart` : Room, Player, RoomSession.
- `lib/services/room_service.dart` : RPC `pr_create_room` / `pr_join_room`, streams Realtime, départ / exclusion / lancement.
- `lib/screens/home_screen.dart` : pseudo, créer ou rejoindre.
- `lib/screens/lobby_screen.dart` : code, liste des joueurs en direct, réglage photos/joueur, lancement par l'hôte.
- `supabase/01_schema.sql` : schéma complet + RLS + Realtime + Storage.

## Règles de travail
- Toujours montrer les changements et attendre le feu vert avant de pousser.
- Fichiers SQL relançables, fournis avant de pousser le code qui en dépend (lancés à la main dans Supabase).
- Ne jamais commiter de clé de signature ni de secret.
- Mettre à jour ce fichier après chaque push.

## État
- v0.1.0 : squelette — accueil, création / jonction de salon, lobby temps réel. Statut `picking` posé au lancement, écran suivant pas encore fait.
- Dossiers `android/` et `web/` pas encore commités : générés par `flutter create` dans la CI. À commiter dès qu'il faut modifier le manifeste Android (permissions photos).

## Prochaines étapes
1. Sélection des photos : `photo_manager` (Android) / `image_picker` (web), compression ~1080 px, écran veto, upload dans `pr-photos`.
2. Partie : tirage des manches par l'hôte, vote avec chrono, révélation, scores.
3. Podium et ménage des fichiers en fin de partie.
