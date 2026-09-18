-- =====================================================================
-- Ticked — real account deletion.
--
-- Run this ONCE in the Supabase SQL Editor (your project > SQL Editor >
-- New query > paste all of this > Run). Until it has been run, the
-- Delete account button in Settings fails with "Account deletion isn't
-- set up on this project yet."
--
-- Why a function instead of deleting from the app: removing a row from
-- auth.users needs the service-role key, and the app ships with the
-- publishable key precisely so it can't do things like that. A
-- SECURITY DEFINER function runs with the privileges of whoever created
-- it (postgres, when you run this in the SQL Editor) rather than the
-- caller's, which is what lets it reach auth.users at all.
--
-- Why that isn't a hole: the function takes no arguments. It reads
-- auth.uid() from the caller's own JWT, so a signed-in user can only
-- ever delete themselves — there is no id to pass and nothing to
-- tamper with.
--
-- The deletes are written out one by one rather than leaning on
-- "on delete cascade", because profiles was created by hand in the
-- dashboard and its foreign key may or may not cascade. Explicit
-- deletes behave the same either way.
-- =====================================================================

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
-- Pinned so the function can't be redirected at a look-alike table via
-- the caller's search_path.
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  -- No session, no deletion. Without this an unauthenticated call would
  -- run `where user_id = null`, which matches nothing, but failing
  -- loudly beats silently reporting success.
  if uid is null then
    raise exception 'Not signed in';
  end if;

  -- Children before parents, same order as schema.sql's drops.
  delete from public.movies_seen where user_id = uid;
  delete from public.profiles where profile_id = uid;
  delete from auth.users where id = uid;
end;
$$;

-- Signed-in callers only. Without the revoke, `anon` would inherit
-- execute from PUBLIC and could call it — harmless today because
-- auth.uid() is null for anon and the function raises, but there's no
-- reason to leave it reachable.
revoke all on function public.delete_own_account() from public;
revoke all on function public.delete_own_account() from anon;
grant execute on function public.delete_own_account() to authenticated;

-- The app reaches this function through PostgREST, which only exposes
-- what's in its schema cache. That cache refreshes on its own, but not
-- instantly — without this the first calls come back PGRST202 ("Could
-- not find the function ... in the schema cache") even though the
-- function exists.
notify pgrst, 'reload schema';
