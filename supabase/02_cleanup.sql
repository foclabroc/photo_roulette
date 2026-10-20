-- =====================================================================
-- Photo Roulette — nettoyage des photos (relançable sans risque)
-- À lancer après 01_schema.sql.
--
-- Supabase interdit de supprimer des fichiers du Storage directement en SQL :
-- c'est donc l'appli qui efface les fichiers, la base dit juste lesquels.
--
-- 1. L'hôte peut supprimer tous les fichiers de son salon (fermeture, exclusion).
-- 2. Salons « oubliés » (hôte parti sans fermer) : à chaque ouverture de l'appli,
--    chacun efface ses propres photos et, s'il est hôte, celles de ses vieux salons,
--    puis ses vieux salons sont supprimés. Personne ne voit les photos des autres.
-- =====================================================================

-- Dossier de premier niveau -> uuid du salon (null si le nom n'est pas un uuid)
create or replace function public.pr_folder_room(p_folder text)
returns uuid
language sql immutable
as $$
  select case
    when p_folder ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then p_folder::uuid
  end;
$$;

-- Fichiers à effacer pour l'utilisateur connecté : salons de plus de 6 h
-- dont il est l'hôte (toutes les photos) ou joueur (ses photos).
create or replace function public.pr_my_stale_photo_paths()
returns setof text
language sql stable security definer set search_path = public
as $$
  select ph.storage_path
  from public.pr_photos ph
  join public.pr_rooms r on r.id = ph.room_id
  join public.pr_players owner on owner.id = ph.owner_player_id
  where r.created_at < now() - interval '6 hours'
    and (r.host_id = auth.uid() or owner.user_id = auth.uid())
  limit 500;
$$;

-- Supprime les vieux salons (plus de 6 h) dont l'utilisateur est l'hôte,
-- et ses lignes de joueur dans les vieux salons des autres.
create or replace function public.pr_delete_my_stale_rooms()
returns int
language plpgsql volatile security definer set search_path = public
as $$
declare v_count int;
begin
  delete from public.pr_rooms
  where host_id = auth.uid() and created_at < now() - interval '6 hours';
  get diagnostics v_count = row_count;

  delete from public.pr_players p
  using public.pr_rooms r
  where p.room_id = r.id
    and p.user_id = auth.uid()
    and r.created_at < now() - interval '6 hours';

  return v_count;
end;
$$;

grant execute on function public.pr_my_stale_photo_paths() to authenticated;
grant execute on function public.pr_delete_my_stale_rooms() to authenticated;

-- Suppression de fichiers : leur propriétaire, ou l'hôte du salon.
drop policy if exists pr_photos_storage_delete on storage.objects;
create policy pr_photos_storage_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'pr-photos'
    and (
      owner_id = auth.uid()::text
      or public.pr_is_room_host(public.pr_folder_room((storage.foldername(name))[1]))
    )
  );

-- L'hôte peut aussi supprimer les lignes pr_photos de son salon.
drop policy if exists pr_photos_delete on public.pr_photos;
create policy pr_photos_delete on public.pr_photos
  for delete to authenticated using (
    public.pr_is_room_host(room_id)
    or exists (select 1 from public.pr_players p
               where p.id = owner_player_id and p.user_id = auth.uid())
  );
