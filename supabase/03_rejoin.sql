-- =====================================================================
-- Photo Roulette — reprise de partie (relançable sans risque)
-- À lancer après 01_schema.sql et 02_cleanup.sql.
--
-- Un joueur dont l'onglet / l'appli a planté peut revenir dans sa partie,
-- même si elle a déjà démarré (photos, manches…). Les nouveaux joueurs,
-- eux, ne peuvent toujours rejoindre qu'au lobby.
-- =====================================================================

-- Reprise par l'id du salon mémorisé sur l'appareil
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
  where p.room_id = p_room
    and p.user_id = auth.uid()
    and r.status <> 'finished';

  if v_player is null then raise exception 'ROOM_NOT_FOUND'; end if;

  return jsonb_build_object('room_id', p_room, 'player_id', v_player, 'code', v_code);
end;
$$;

grant execute on function public.pr_rejoin_room(uuid) to authenticated;

-- Rejoindre par code : un joueur déjà inscrit revient quel que soit le statut ;
-- un nouveau joueur n'entre que si le salon est encore au lobby.
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
  where code = upper(btrim(p_code)) and status <> 'finished';
  if not found then raise exception 'ROOM_NOT_FOUND'; end if;

  select id into v_player from public.pr_players
  where room_id = v_room.id and user_id = v_uid;

  if v_player is not null then
    update public.pr_players set name = v_name where id = v_player;
  else
    if v_room.status <> 'lobby' then raise exception 'ROOM_STARTED'; end if;
    if (select count(*) from public.pr_players where room_id = v_room.id) >= 12 then
      raise exception 'ROOM_FULL';
    end if;
    insert into public.pr_players (room_id, user_id, name) values (v_room.id, v_uid, v_name)
    returning id into v_player;
  end if;

  return jsonb_build_object('room_id', v_room.id, 'player_id', v_player, 'code', v_room.code);
end;
$$;
