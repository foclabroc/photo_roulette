-- =====================================================================
-- Photo Roulette — manches, votes, scores (relançable sans risque)
-- À lancer après 01, 02 et 03.
--
-- Tout le déroulé est décidé par le serveur : tirage des manches, chrono,
-- points. L'appli ne fait qu'afficher et envoyer les votes.
-- Points : bonne réponse 100 + bonus rapidité jusqu'à 50 ;
--          le propriétaire gagne 20 par joueur trompé.
-- =====================================================================

alter table public.pr_rooms add column if not exists current_round int not null default -1;
alter table public.pr_rooms add column if not exists total_rounds  int not null default 0;
alter table public.pr_rooms add column if not exists vote_seconds  int not null default 15;

alter table public.pr_rounds add column if not exists storage_path    text;
alter table public.pr_rounds add column if not exists ends_at         timestamptz;
alter table public.pr_rounds add column if not exists owner_player_id uuid;  -- rempli à la révélation
alter table public.pr_rounds alter column started_at drop not null;
alter table public.pr_rounds alter column started_at drop default;

alter table public.pr_votes add column if not exists room_id uuid references public.pr_rooms(id) on delete cascade;
alter table public.pr_votes add column if not exists points  int not null default 0;
create index if not exists pr_votes_room_idx on public.pr_votes(room_id);

-- Les votes ne s'écrivent plus que par pr_vote (points calculés côté serveur)
drop policy if exists pr_votes_insert on public.pr_votes;
-- Les manches ne s'écrivent plus que par les RPC
drop policy if exists pr_rounds_write on public.pr_rounds;

-- ---------- Démarrage : tirage des manches ----------------------------

create or replace function public.pr_start_rounds(p_room uuid)
returns int
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_room   public.pr_rooms%rowtype;
  v_last   uuid;
  v_idx    int := 0;
  v_photo  record;
begin
  select * into v_room from public.pr_rooms where id = p_room for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if v_room.host_id <> auth.uid() then raise exception 'NOT_HOST'; end if;
  if v_room.status <> 'picking' then raise exception 'BAD_STATUS'; end if;

  delete from public.pr_rounds where room_id = p_room;

  -- Mélange en évitant deux photos du même joueur à la suite quand c'est possible
  create temp table if not exists pr_tmp_pool (id uuid, owner uuid, path text) on commit drop;
  delete from pr_tmp_pool;
  insert into pr_tmp_pool
    select id, owner_player_id, storage_path from public.pr_photos where room_id = p_room;

  loop
    select * into v_photo from pr_tmp_pool
    order by (owner = v_last), random()
    limit 1;
    exit when not found;

    insert into public.pr_rounds (room_id, round_index, photo_id, storage_path)
    values (p_room, v_idx, v_photo.id, v_photo.path);

    delete from pr_tmp_pool where id = v_photo.id;
    v_last := v_photo.owner;
    v_idx := v_idx + 1;
  end loop;

  if v_idx = 0 then raise exception 'NO_PHOTOS'; end if;

  update public.pr_players set score = 0 where room_id = p_room;

  update public.pr_rounds
  set started_at = now(), ends_at = now() + make_interval(secs => v_room.vote_seconds)
  where room_id = p_room and round_index = 0;

  update public.pr_rooms
  set status = 'playing', current_round = 0, total_rounds = v_idx
  where id = p_room;

  return v_idx;
end;
$$;

-- ---------- Révélation (interne) --------------------------------------

create or replace function public.pr__reveal(p_round uuid)
returns void
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_owner uuid;
  v_room  uuid;
  v_wrong int;
begin
  -- Une seule révélation par manche
  update public.pr_rounds r
  set revealed = true,
      owner_player_id = ph.owner_player_id
  from public.pr_photos ph
  where r.id = p_round and ph.id = r.photo_id and not r.revealed
  returning r.owner_player_id, r.room_id into v_owner, v_room;

  if v_owner is null then return; end if;

  -- Points des votants
  update public.pr_players p
  set score = p.score + v.points
  from public.pr_votes v
  where v.round_id = p_round and v.voter_player_id = p.id and v.points > 0;

  -- Le propriétaire gagne 20 par joueur trompé
  select count(*) into v_wrong from public.pr_votes
  where round_id = p_round and guessed_player_id <> v_owner;
  update public.pr_players set score = score + 20 * v_wrong where id = v_owner;
end;
$$;

revoke all on function public.pr__reveal(uuid) from public, anon, authenticated;

-- ---------- Vote --------------------------------------------------------

create or replace function public.pr_vote(p_round uuid, p_guess uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_round  public.pr_rounds%rowtype;
  v_room   public.pr_rooms%rowtype;
  v_voter  uuid;
  v_owner  uuid;
  v_points int := 0;
  v_left   double precision;
  v_voters int;
  v_votes  int;
begin
  select * into v_round from public.pr_rounds where id = p_round;
  if not found then raise exception 'ROUND_NOT_FOUND'; end if;
  select * into v_room from public.pr_rooms where id = v_round.room_id;
  if v_room.current_round <> v_round.round_index or v_round.revealed then
    raise exception 'ROUND_CLOSED';
  end if;
  -- 2 s de tolérance réseau après la fin du chrono
  if now() > v_round.ends_at + interval '2 seconds' then raise exception 'ROUND_CLOSED'; end if;

  select id into v_voter from public.pr_players
  where room_id = v_round.room_id and user_id = auth.uid();
  if v_voter is null then raise exception 'NOT_MEMBER'; end if;

  select owner_player_id into v_owner from public.pr_photos where id = v_round.photo_id;
  if v_voter = v_owner then raise exception 'OWN_PHOTO'; end if;

  if v_owner = p_guess then
    v_left := greatest(0, extract(epoch from (v_round.ends_at - now())));
    v_points := 100 + floor(50 * least(1, v_left / greatest(v_room.vote_seconds, 1)))::int;
  end if;

  insert into public.pr_votes (round_id, room_id, voter_player_id, guessed_player_id, points)
  values (p_round, v_round.room_id, v_voter, p_guess, v_points)
  on conflict (round_id, voter_player_id) do nothing;

  -- Tout le monde a voté (sauf le propriétaire) : révélation immédiate
  select count(*) into v_voters from public.pr_players
  where room_id = v_round.room_id and id <> v_owner;
  select count(*) into v_votes from public.pr_votes where round_id = p_round;
  if v_votes >= v_voters then
    perform public.pr__reveal(p_round);
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

-- ---------- Fin du chrono : n'importe quel joueur déclenche la révélation ----------

create or replace function public.pr_reveal_round(p_round uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_round public.pr_rounds%rowtype;
begin
  select * into v_round from public.pr_rounds where id = p_round;
  if not found then raise exception 'ROUND_NOT_FOUND'; end if;
  if not public.pr_is_room_member(v_round.room_id) then raise exception 'NOT_MEMBER'; end if;
  if v_round.revealed then return jsonb_build_object('ok', true); end if;
  -- L'hôte peut révéler à tout moment ; les autres seulement après le chrono
  if not public.pr_is_room_host(v_round.room_id) and now() < v_round.ends_at then
    raise exception 'TOO_EARLY';
  end if;
  perform public.pr__reveal(p_round);
  return jsonb_build_object('ok', true);
end;
$$;

-- ---------- Manche suivante / fin de partie (hôte) --------------------

create or replace function public.pr_next_round(p_room uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public
as $$
declare
  v_room public.pr_rooms%rowtype;
  v_next int;
begin
  select * into v_room from public.pr_rooms where id = p_room for update;
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;
  if v_room.host_id <> auth.uid() then raise exception 'NOT_HOST'; end if;
  if v_room.status <> 'playing' then raise exception 'BAD_STATUS'; end if;

  -- La manche en cours doit être révélée (sinon on la révèle d'abord)
  perform public.pr__reveal(id) from public.pr_rounds
  where room_id = p_room and round_index = v_room.current_round and not revealed;

  v_next := v_room.current_round + 1;
  if v_next >= v_room.total_rounds then
    update public.pr_rooms set status = 'finished' where id = p_room;
    return jsonb_build_object('finished', true);
  end if;

  update public.pr_rounds
  set started_at = now(), ends_at = now() + make_interval(secs => v_room.vote_seconds)
  where room_id = p_room and round_index = v_next;
  update public.pr_rooms set current_round = v_next where id = p_room;

  return jsonb_build_object('finished', false, 'round', v_next);
end;
$$;

grant execute on function public.pr_start_rounds(uuid)  to authenticated;
grant execute on function public.pr_vote(uuid, uuid)    to authenticated;
grant execute on function public.pr_reveal_round(uuid)  to authenticated;
grant execute on function public.pr_next_round(uuid)    to authenticated;

-- ---------- Reprise : une partie terminée reste accessible pour le podium ----------

create or replace function public.pr_rejoin_room(p_room uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_player uuid;
  v_code   text;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select p.id, r.code into v_player, v_code
  from public.pr_players p
  join public.pr_rooms r on r.id = p.room_id
  where p.room_id = p_room and p.user_id = auth.uid();

  if v_player is null then raise exception 'ROOM_NOT_FOUND'; end if;

  return jsonb_build_object('room_id', p_room, 'player_id', v_player, 'code', v_code);
end;
$$;
