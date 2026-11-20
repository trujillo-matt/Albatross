-- Fixes new-user creation. The existing handle_new_user() trigger function referenced "profiles" without a schema and
-- had no pinned search_path. Supabase Auth runs it with search_path = auth, so every insert into auth.users made by Auth
-- itself (public signup, admin createUser) failed with: relation "profiles" does not exist. Found on 2026-11-20 when the
-- admin-players function could not create a managed player.
--
-- Behavior is otherwise unchanged (same columns, on conflict do nothing). The only addition: if the signup metadata has
-- no full_name, fall back to display_name, which the admin-players function sends.
--
-- Also pins search_path on the two trigger functions from migration 002 (flagged by the Supabase security advisor).
begin;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name, username)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), new.raw_user_meta_data->>'display_name', ''),
    new.raw_user_meta_data->>'username'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

alter function public.trg_round_completed() set search_path = public;
alter function public.trg_matchup_round_linked() set search_path = public;

commit;
