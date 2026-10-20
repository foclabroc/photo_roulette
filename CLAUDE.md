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
- `lib/screens/lobby_screen.dart` : écran du salon ; affiche le lobby (code, joueurs, réglage photos/joueur, lancement) ou `PickingView` selon le statut.
- `lib/screens/picking_view.dart` : tirage + veto (Refuser / Garder), miniatures retirables, joueurs prêts, bouton « Lancer les manches » pour l'hôte.
- `lib/services/photo_source*.dart` : source de photos par import conditionnel — `photo_manager` sur Android (galerie entière), `image_picker` sur web (lot choisi). Réduction ~1080 px JPEG q80 faite par la plateforme.
- `lib/models/photo.dart` : MyPhoto.
- `android/app/src/main/AndroidManifest.xml` : seul fichier Android commité (INTERNET + permissions photos) ; le reste est généré par `flutter create` en CI.
- `supabase/01_schema.sql` : schéma complet + RLS + Realtime + Storage.

## Règles de travail
- Toujours montrer les changements et attendre le feu vert avant de pousser.
- Fichiers SQL relançables, fournis avant de pousser le code qui en dépend (lancés à la main dans Supabase).
- Ne jamais commiter de clé de signature ni de secret.
- Mettre à jour ce fichier après chaque push.

## État
- v0.1.0 : squelette — accueil, création / jonction de salon, lobby temps réel. Testé OK sur le web (2 joueurs).
- v0.2.0 : sélection des photos (tirage + veto), upload dans `pr-photos`, drapeau `ready` synchronisé, statut `playing` posé par l'hôte quand tout le monde est prêt. Bouton d'exclusion limité au lobby. Pas de nouveau SQL.
- Site web : https://foclabroc.github.io/photo_roulette/ (Pages en source GitHub Actions, repo public).
- Le code n'est pas compilé avant push (pas de SDK Flutter dans l'environnement de Claude) : la CI fait foi.

## Prochaines étapes
1. Partie : tirage des manches par l'hôte (RPC qui mélange les photos), affichage photo, vote avec chrono, révélation, scores.
2. Podium et ménage des fichiers du bucket en fin de partie (les fichiers d'un joueur qui quitte restent pour l'instant).
