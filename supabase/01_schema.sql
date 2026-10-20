-- =====================================================================
-- Photo Roulette — schéma Supabase (relançable sans risque)
-- Tables préfixées pr_ : peut cohabiter avec un autre projet Supabase.
-- Prérequis : Authentication > Sign In / Providers > "Allow anonymous sign-ins" activé.
-- =====================================================================

-- ---------- Tables ----------------------------------------------------

create table if not exists public.pr_rooms (
  id                uuid primary key default gen_random_uuid(),
  code              text not null unique,
  host_id           uuid not null default auth.uid(),
  status            text not null default 'lobby'
                    check (status in ('lobby', 'picking', 'playing', 'finished')),
  photos_per_player int  not null default 5 check (photos_per_player between 1 and 20),
  created_at        timestamptz not null default now()
);

create table if not exists public.pr_players (
  id        uuid primary key default gen_random_uuid(),
  room_id   uuid not null references public.pr_rooms(id) on delete cascade,
  user_id   uuid not null default auth.uid(),
  name      text not null check (char_length(name) between 1 and 20),
  score     int  not null default 0,
  ready     boolean not null default false,
  joined_at timestamptz not null default now(),
  unique (room_id, user_id)
);

create table if not exists public.pr_photos (
  id              uuid primary key default gen_random_uuid(),
  room_id         uuid not null references public.pr_rooms(id) on delete cascade,
  owner_player_id uuid not null references public.pr_players(id) on delete cascade,
  storage_path    text not null,
  created_at      timestamptz not null default now()
);

create table if not exists public.pr_rounds (
  id          uuid primary key default gen_random_uuid(),
  room_id     uuid not null references public.pr_rooms(id) on delete cascade,
  round_index int  not null,
  photo_id    uuid not null references public.pr_photos(id) on delete cascade,
  started_at  timestamptz not null default now(),
  revealed    boolean not null default false,
  unique (room_id, round_index)
);

create table if not exists public.pr_votes (
  round_id          uuid not null references public.pr_rounds(id) on delete cascade,
  voter_player_id   uuid not null references public.pr_players(id) on delete cascade,
  guessed_player_id uuid not null references public.pr_players(id) on delete cascade,
  created_at        timestamptz not null default now(),
  primary key (round_id, voter_player_id)
);

create index if not exists pr_players_room_idx on public.pr_players(room_id);
create index if not exists pr_players_user_idx on public.pr_players(user_id);
create index if not exists pr_photos_room_idx  on public.pr_photos(room_id);
create index if not exists pr_rounds_room_idx  on public.pr_rounds(room_id);

-- ---------- Fonctions utilitaires -------------------------------------

-- L'utilisateur connecté fait-il partie du salon ?
create or replace function public.pr_is_room_member(p_room uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.pr_players
    where room_id = p_room and user_id = auth.uid()
  );
$$;

-- L'utilisateur connecté est-il l'hôte du salon ?
create or replace function public.pr_is_room_host(p_room uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.pr_rooms
    where id = p_room and host_id = auth.uid()
  );
$$;

-- Code de salon : 5 caractères sans caractères ambigus (pas de 0/O, 1/I/L)
create or replace function public.pr_random_code()
returns text
language plpgsql volatile
as $$
declare
  chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  result text := '';
begin
  for i in 1..5 loop
    result := result || substr(chars, 1 + floor(random() * length(chars))::int, 1);
  end loop;
  return result;
end;
$$;

-- Créer un salon : crée la partie + le joueur hôte
create or replace function public.pr_create_room(p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_name   text := btrim(coalesce(p_name, ''));
  v_code   text;
  v_room   uuid;
  v_player uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if char_length(v_name) = 0 then raise exception 'NAME_REQUIRED'; end if;
  v_name := left(v_name, 20);

  loop
    v_code := public.pr_random_code();
    exit when not exists (select 1 from public.pr_rooms where code = v_code);
  end loop;

  insert into public.pr_rooms (code, host_id) values (v_code, v_uid)
  returning id into v_room;

  insert into public.pr_players (room_id, user_id, name) values (v_room, v_uid, v_name)
  returning id into v_player;

  return jsonb_build_object('room_id', v_room, 'player_id', v_player, 'code', v_code);
end;
$$;

-- Rejoindre un salon par son code (uniquement s'il est encore dans le lobby)
create or replace function public.pr_join_room(p_code text, p_name text)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_name   text := left(btrim(coalesce(p_name, '')), 20);
  v_room   public.pr_rooms%rowtype;
  v_player uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if char_length(v_name) = 0 then raise exception 'NAME_REQUIRED'; end if;

  select * into v_room from public.pr_rooms
  where code = upper(btrim(p_code)) and status = 'lobby';
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;

  -- Déjà dans le salon : on met juste le pseudo à jour
  select id into v_player from public.pr_players
  where room_id = v_room.id and user_id = v_uid;

  if v_player is not null then
    update public.pr_players set name = v_name where id = v_player;
  else
    if (select count(*) from public.pr_players where room_id = v_room.id) >= 12 then
      raise exception 'ROOM_FULL';
    end if;
    insert into public.pr_players (room_id, user_id, name) values (v_room.id, v_uid, v_name)
    returning id into v_player;
  end if;

  return jsonb_build_object('room_id', v_room.id, 'player_id', v_player, 'code', v_room.code);
end;
$$;

-- Ménage : supprime les salons de plus de 24 h (photos en base supprimées en cascade)
create or replace function public.pr_cleanup_old_rooms()
returns int
language plpgsql volatile security definer set search_path = public
as $$
declare v_count int;
begin
  delete from public.pr_rooms where created_at < now() - interval '24 hours';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.pr_cleanup_old_rooms() from public, anon, authenticated;
grant execute on function public.pr_create_room(text)     to authenticated;
grant execute on function public.pr_join_room(text, text) to authenticated;

-- ---------- RLS -------------------------------------------------------

alter table public.pr_rooms   enable row level security;
alter table public.pr_players enable row level security;
alter table public.pr_photos  enable row level security;
alter table public.pr_rounds  enable row level security;
alter table public.pr_votes   enable row level security;

-- Salons : visibles par leurs membres, modifiables / supprimables par l'hôte.
-- Pas de policy insert : création uniquement via pr_create_room.
drop policy if exists pr_rooms_select on public.pr_rooms;
create policy pr_rooms_select on public.pr_rooms
  for select to authenticated using (public.pr_is_room_member(id));

drop policy if exists pr_rooms_update on public.pr_rooms;
create policy pr_rooms_update on public.pr_rooms
  for update to authenticated using (host_id = auth.uid()) with check (host_id = auth.uid());

drop policy if exists pr_rooms_delete on public.pr_rooms;
create policy pr_rooms_delete on public.pr_rooms
  for delete to authenticated using (host_id = auth.uid());

-- Joueurs : visibles par les membres ; chacun modifie sa ligne ;
-- on peut partir, et l'hôte peut exclure.
drop policy if exists pr_players_select on public.pr_players;
create policy pr_players_select on public.pr_players
  for select to authenticated using (public.pr_is_room_member(room_id));

drop policy if exists pr_players_update on public.pr_players;
create policy pr_players_update on public.pr_players
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists pr_players_delete on public.pr_players;
create policy pr_players_delete on public.pr_players
  for delete to authenticated
  using (user_id = auth.uid() or public.pr_is_room_host(room_id));

-- Photos : visibles par les membres ; chacun ajoute / retire les siennes.
drop policy if exists pr_photos_select on public.pr_photos;
create policy pr_photos_select on public.pr_photos
  for select to authenticated using (public.pr_is_room_member(room_id));

drop policy if exists pr_photos_insert on public.pr_photos;
create policy pr_photos_insert on public.pr_photos
  for insert to authenticated with check (
    exists (select 1 from public.pr_players p
            where p.id = owner_player_id and p.room_id = pr_photos.room_id
              and p.user_id = auth.uid())
  );

drop policy if exists pr_photos_delete on public.pr_photos;
create policy pr_photos_delete on public.pr_photos
  for delete to authenticated using (
    exists (select 1 from public.pr_players p
            where p.id = owner_player_id and p.user_id = auth.uid())
  );

-- Manches : visibles par les membres, pilotées par l'hôte.
drop policy if exists pr_rounds_select on public.pr_rounds;
create policy pr_rounds_select on public.pr_rounds
  for select to authenticated using (public.pr_is_room_member(room_id));

drop policy if exists pr_rounds_write on public.pr_rounds;
create policy pr_rounds_write on public.pr_rounds
  for all to authenticated
  using (public.pr_is_room_host(room_id)) with check (public.pr_is_room_host(room_id));

-- Votes : visibles par les membres ; chacun vote une fois pour lui-même.
drop policy if exists pr_votes_select on public.pr_votes;
create policy pr_votes_select on public.pr_votes
  for select to authenticated using (
    exists (select 1 from public.pr_rounds r
            where r.id = round_id and public.pr_is_room_member(r.room_id))
  );

drop policy if exists pr_votes_insert on public.pr_votes;
create policy pr_votes_insert on public.pr_votes
  for insert to authenticated with check (
    exists (select 1 from public.pr_players p
            where p.id = voter_player_id and p.user_id = auth.uid())
  );

-- ---------- Realtime --------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array['pr_rooms', 'pr_players', 'pr_photos', 'pr_rounds', 'pr_votes'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end;
$$;

-- ---------- Storage (photos) ------------------------------------------
-- Bucket privé ; chemin des fichiers : <room_id>/<player_id>/<fichier>.jpg

insert into storage.buckets (id, name, public)
values ('pr-photos', 'pr-photos', false)
on conflict (id) do nothing;

drop policy if exists pr_photos_storage_select on storage.objects;
create policy pr_photos_storage_select on storage.objects
  for select to authenticated using (
    bucket_id = 'pr-photos'
    and public.pr_is_room_member(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists pr_photos_storage_insert on storage.objects;
create policy pr_photos_storage_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'pr-photos'
    and public.pr_is_room_member(((storage.foldername(name))[1])::uuid)
  );

drop policy if exists pr_photos_storage_delete on storage.objects;
create policy pr_photos_storage_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'pr-photos' and owner_id = auth.uid()::text
  );

-- ---------- Ménage ----------------------------------------------------
-- Ne pas planifier pr_cleanup_old_rooms avec pg_cron : supprimer les salons en SQL
-- laisserait leurs fichiers orphelins dans le Storage. Le ménage passe par l'appli
-- (voir 02_cleanup.sql).
