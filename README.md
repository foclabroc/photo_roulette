# Photo Roulette

Jeu de soirée multijoueur : chacun rejoint un salon depuis son téléphone, l'appli tire des photos dans les galeries des joueurs, et tout le monde devine à qui appartient chaque photo.

Flutter (Android + web) · Supabase (Auth anonyme, Postgres, Realtime, Storage).

## Mise en place Supabase

1. **Authentication → Sign In / Providers** : activer *Allow anonymous sign-ins*.
2. **SQL Editor** : lancer `supabase/01_schema.sql` puis `supabase/02_cleanup.sql` (relançables sans risque).
3. Récupérer l'URL du projet et la clé `anon` (Project Settings → API).

Toutes les tables sont préfixées `pr_` et le bucket s'appelle `pr-photos` : le schéma peut cohabiter avec un autre projet dans la même base.

## Lancer en local

```bash
flutter create . --platforms=android,web --project-name photo_roulette --org com.foclabroc   # une seule fois
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxx
```

## GitHub

- Secrets du repo : `SUPABASE_URL`, `SUPABASE_ANON_KEY`.
- **Settings → Pages → Source : GitHub Actions**.
- `web.yml` : build web + déploiement Pages à chaque push sur `main`.
- `apk.yml` : build de l'APK à la demande (onglet Actions).

## Déroulé du jeu

Lobby (code à 5 caractères) → sélection des photos (hasard + veto ; sur web, sélection manuelle d'un lot) → manches : photo affichée, vote, révélation → scores → podium.
