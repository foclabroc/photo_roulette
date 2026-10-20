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
- `lib/services/photo_source*.dart` : source de photos par import conditionnel — `photo_manager` sur Android (galerie entière), `image_picker` sur web (lot choisi, 40 max). Réduction ~1080 px JPEG q80 : thumbnail natif sur Android ; sur web, une photo à la fois via canvas au moment du tirage (réduire tout le lot à la sélection faisait planter l'onglet mobile, écran blanc).
- `lib/models/photo.dart` : MyPhoto.
- `android/app/src/main/AndroidManifest.xml` : seul fichier Android commité (INTERNET + permissions photos) ; le reste est généré par `flutter create` en CI.
- `supabase/01_schema.sql` : schéma complet + RLS + Realtime + Storage.
- `lib/utils/last_room.dart` : dernier salon mémorisé (shared_preferences) pour la reprise.
- `supabase/03_rejoin.sql` : `pr_rejoin_room` (reprise par id) + `pr_join_room` revu (un membre revient quel que soit le statut ; nouveau joueur seulement au lobby, sinon ROOM_STARTED).
- `supabase/02_cleanup.sql` : nettoyage des photos (l'hôte peut effacer les fichiers de son salon ; RPC `pr_my_stale_photo_paths` / `pr_delete_my_stale_rooms` pour les salons de plus de 6 h).

## Règles de travail
- Toujours montrer les changements et attendre le feu vert avant de pousser.
- Fichiers SQL relançables, fournis avant de pousser le code qui en dépend (lancés à la main dans Supabase).
- Ne jamais commiter de clé de signature ni de secret.
- Mettre à jour ce fichier après chaque push.

## État
- v0.1.0 : squelette — accueil, création / jonction de salon, lobby temps réel. Testé OK sur le web (2 joueurs).
- v0.2.0 : sélection des photos (tirage + veto), upload dans `pr-photos`, drapeau `ready` synchronisé, statut `playing` posé par l'hôte quand tout le monde est prêt. Bouton d'exclusion limité au lobby. Pas de nouveau SQL.
- Correctifs (6d8a338) : liste des joueurs dédoublonnée par id (le flux Realtime renvoyait parfois 2× la même ligne) ; reconnexion automatique des flux après une coupure (erreur 1006 fréquente sur mobile), bandeau « reconnexion… ».
- Test à plusieurs : deux onglets du même navigateur = même session anonyme = même joueur ; utiliser un autre appareil ou un onglet privé.
- Site web : https://foclabroc.github.io/photo_roulette/ (Pages en source GitHub Actions, repo public).
- Le code n'est pas compilé avant push (pas de SDK Flutter dans l'environnement de Claude) : la CI fait foi.

- Nettoyage des fichiers : l'hôte qui ferme efface toutes les photos du salon ; un joueur qui part ou est exclu voit ses photos effacées ; à chaque ouverture de l'accueil, ménage silencieux des salons de plus de 6 h (mes photos + celles des salons dont je suis l'hôte). Supabase interdit d'effacer des fichiers en SQL, d'où ce passage par l'appli. `deleteRoomFiles` à appeler aussi en fin de partie (podium).
- Reprise de partie : l'accueil affiche « Partie en cours · CODE → Reprendre » si le dernier salon mémorisé est toujours accessible (plantage, onglet fermé, appli tuée). Mémoire effacée quand on quitte, qu'on est exclu ou que le salon est fermé.
- Écran blanc web corrigé (c00e6a6) : réduction des photos une à une au tirage.

## Prochaines étapes
1. Partie : tirage des manches par l'hôte (RPC qui mélange les photos), affichage photo, vote avec chrono, révélation, scores.
2. Podium, puis appel de `deleteRoomFiles` en fin de partie.
3. Cache des photos côté téléphone pendant la partie (limiter la bande passante, 5 Go/mois en gratuit).
