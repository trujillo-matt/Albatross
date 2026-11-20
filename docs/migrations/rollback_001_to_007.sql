-- Reverses migrations 001 to 007. Written from the live schema captured on 2026-11-17 (original policies restored
-- verbatim, including the bugs). Run only if you need to back out; it drops the new tables and columns, and with
-- them any data in them (access codes, audit log, sides, spectator tokens, course ratings).
begin;

-- 007: restores the ORIGINAL handle_new_user. Note the original is the version that fails whenever Supabase Auth creates a
-- user (relation "profiles" does not exist), so running this re-breaks new-user creation. Skip it unless you must.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer as $$
begin
  insert into profiles (id, display_name, username)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), new.raw_user_meta_data->>'username')
  on conflict (id) do nothing;
  return new;
end;
$$;
alter function public.trg_round_completed() reset search_path;
alter function public.trg_matchup_round_linked() reset search_path;

-- 006 (restore the default of PUBLIC execute)
grant execute on function
  cast_captain_votes(uuid, uuid[]), finalize_captains(uuid, uuid[]), draft_pick(uuid, uuid, boolean),
  set_hole_score(uuid, int, int), set_pairings(uuid, uuid[], uuid[]), set_spectator_link(uuid, boolean),
  admin_code_status(uuid), admin_set_hole_score(uuid, int, int, text), admin_recompute_matchup(uuid), admin_audit_log(uuid),
  trg_round_completed(), trg_matchup_round_linked(), tp_guard_update() to public;

-- 005
drop trigger if exists tournament_players_guard on tournament_players;
drop function if exists tp_guard_update();
drop function if exists set_pairings(uuid, uuid[], uuid[]);
drop policy if exists "tournament members can read co-member profiles" on profiles;
drop policy if exists "tournament members can read matchup rounds" on rounds;
drop function if exists shares_tournament_with(uuid);
drop function if exists is_tournament_creator(uuid);
drop policy if exists "members can read votes" on tournament_captain_votes;
create policy "members can read votes" on tournament_captain_votes for select using (
  exists (select 1 from tournament_players tp where tp.tournament_id = tp.tournament_id and tp.user_id = auth.uid()));
drop policy if exists "members can read matchups" on tournament_matchups;
create policy "members can read matchups" on tournament_matchups for select using (
  exists (select 1 from tournament_players tp where tp.tournament_id = tp.tournament_id and tp.user_id = auth.uid()));
alter table rounds drop column if exists course_rating;
alter table rounds drop column if exists slope_rating;
do $$ begin alter publication supabase_realtime drop table tournament_teams; exception when others then null; end $$;

-- 004
drop function if exists admin_audit_log(uuid);
drop function if exists get_public_standings(text);
drop function if exists set_spectator_link(uuid, boolean);
alter table tournaments drop column if exists public_token;

-- 003
drop function if exists admin_recompute_matchup(uuid);
drop function if exists admin_set_hole_score(uuid, int, int, text);
drop function if exists admin_code_status(uuid);
drop function if exists is_tournament_admin(uuid);
drop table if exists tournament_audit_log;
drop table if exists code_redeem_attempts;
drop table if exists player_access_codes;
alter table profiles drop column if exists claimed_at;
alter table profiles drop column if exists managed_by;
alter table profiles drop column if exists is_managed;

-- 002
drop trigger if exists rounds_completed on rounds;
drop trigger if exists matchup_round_linked on tournament_matchup_rounds;
drop function if exists trg_round_completed();
drop function if exists trg_matchup_round_linked();
drop function if exists compute_matchup_result(uuid);
drop function if exists set_hole_score(uuid, int, int);
drop function if exists draft_pick(uuid, uuid, boolean);
drop function if exists finalize_captains(uuid, uuid[]);
drop function if exists cast_captain_votes(uuid, uuid[]);
alter table tournament_matchups drop column if exists scorer_user_id;
alter table tournament_courses drop column if exists course_id;
-- (002 also corrected points_to_win on non-complete tournaments still at 9.5; that data change is not reversed.)

-- 001
drop index if exists tournament_teams_one_per_side;
alter table tournament_teams drop constraint if exists tournament_teams_side_check;
alter table tournament_teams drop column if exists side;

commit;
