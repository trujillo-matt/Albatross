-- Fixes found by auditing the LIVE schema and policies (2026-11-17). Apply after 001 to 004.
--
-- STATUS: NOT APPLIED to the live project. Proven only against a local copy of the live schema
-- (docs/tests/00_stub_schema.sql), where docs/tests/05_demonstrate_bugs.sql shows each bug is real before this
-- runs and docs/tests/20_rls_test.sql shows it is gone after.
--
-- What it changes, in plain terms:
--  1. Closes a cross-tournament leak: two read policies compared tp.tournament_id to itself, so any player in
--     any tournament could read every tournament's captain votes and matchups.
--  2. Stops players from promoting themselves: tp_update let a player edit ANY column of their own
--     tournament_players row (is_admin, team_id, ...). A guard trigger now limits non-creators to accepting or
--     declining their own invite.
--  3. Lets captains actually draft and set pairings, which the existing creator-only policies silently blocked,
--     through audited security definer functions (draft_pick is in 002; set_pairings is here).
--  4. Lets tournament members read each other's names (profiles were readable only by their owner).
--  5. Lets tournament members read the in-progress cards of their own tournament (needed for the admin Scores
--     tab and live match status). Cards outside a tournament are unchanged.
--  6. Adds rounds.course_rating and rounds.slope_rating, which the iOS app already sends but the table lacks.
--  7. Adds tournament_teams to realtime so team/captain changes push to clients.

begin;

-- 6. Columns the iOS client already writes.
alter table rounds add column if not exists course_rating numeric;
alter table rounds add column if not exists slope_rating int;

-- Helpers (security definer so they work for users who cannot read the underlying rows under RLS).
create or replace function is_tournament_creator(tid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from tournaments where id = tid and creator_user_id = auth.uid())
$$;

create or replace function shares_tournament_with(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_user = auth.uid()
      or exists (select 1 from tournament_players mine
                   join tournament_players theirs on theirs.tournament_id = mine.tournament_id
                  where mine.user_id = auth.uid() and mine.invite_status = 'accepted' and theirs.user_id = p_user)
$$;

-- 1. Fix the self-comparison policies.
drop policy if exists "members can read votes" on tournament_captain_votes;
create policy "members can read votes" on tournament_captain_votes for select using (
  is_tournament_member(tournament_id) or is_tournament_creator(tournament_id));

drop policy if exists "members can read matchups" on tournament_matchups;
create policy "members can read matchups" on tournament_matchups for select using (
  is_tournament_member(tournament_id) or is_tournament_creator(tournament_id));

-- 2. Guard tournament_players updates made directly by clients. Functions that run as the table owner
--    (draft_pick, finalize_captains, edge functions) are unaffected: only the client roles are restricted.
-- Deliberately NOT security definer: current_user must be the role that issued the UPDATE (authenticated), not the
-- function owner. Functions that run as the owner (draft_pick, finalize_captains) therefore bypass the guard.
create or replace function tp_guard_update() returns trigger language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if is_tournament_creator(old.tournament_id) then return new; end if;     -- the commissioner may change anything
  if new.tournament_id is distinct from old.tournament_id or new.user_id is distinct from old.user_id
     or new.team_id is distinct from old.team_id or new.is_admin is distinct from old.is_admin
     or new.draft_position is distinct from old.draft_position then
    raise exception 'players can only answer their own invite';
  end if;
  if new.invite_status is distinct from old.invite_status
     and not (old.invite_status = 'pending' and new.invite_status in ('accepted', 'declined')) then
    raise exception 'invalid invite change';
  end if;
  return new;
end $$;
drop trigger if exists tournament_players_guard on tournament_players;
create trigger tournament_players_guard before update on tournament_players
  for each row execute function tp_guard_update();

-- 3. Pairings: the commissioner, an admin, or either team's captain; sides equal size 1 or 2; players must be
--    on the side they are listed for.
create or replace function set_pairings(p_matchup uuid, p_team_a uuid[], p_team_b uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare m tournament_matchups%rowtype; ok boolean;
begin
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  select is_tournament_admin(m.tournament_id)
      or exists (select 1 from tournament_teams where id in (m.team_a_id, m.team_b_id) and captain_user_id = auth.uid())
    into ok;
  if not ok then raise exception 'only an admin or a captain can set pairings'; end if;
  if m.status = 'complete' then raise exception 'match is already complete'; end if;
  if coalesce(array_length(p_team_a, 1), 0) not between 1 and 2
     or coalesce(array_length(p_team_a, 1), 0) <> coalesce(array_length(p_team_b, 1), 0) then
    raise exception 'pick the same number of players (1 or 2) on each side';
  end if;
  if (select count(*) from tournament_players where tournament_id = m.tournament_id and team_id = m.team_a_id
        and invite_status = 'accepted' and user_id = any (p_team_a)) <> array_length(p_team_a, 1)
     or (select count(*) from tournament_players where tournament_id = m.tournament_id and team_id = m.team_b_id
        and invite_status = 'accepted' and user_id = any (p_team_b)) <> array_length(p_team_b, 1) then
    raise exception 'players must belong to the team they are paired for';
  end if;
  update tournament_matchups set team_a_player_ids = p_team_a, team_b_player_ids = p_team_b,
         status = 'active', updated_at = now() where id = p_matchup;
end $$;

-- 4. Co-members can read each other's profile rows.
drop policy if exists "tournament members can read co-member profiles" on profiles;
create policy "tournament members can read co-member profiles" on profiles for select using (shares_tournament_with(id));

-- 5. Members can read the cards linked to their tournament's matchups (in progress included).
drop policy if exists "tournament members can read matchup rounds" on rounds;
create policy "tournament members can read matchup rounds" on rounds for select using (
  matchup_id is not null and exists (
    select 1 from tournament_matchups m
     where m.id = rounds.matchup_id and (is_tournament_member(m.tournament_id) or is_tournament_creator(m.tournament_id))));

-- 7. Realtime for teams.
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'tournament_teams') then
    alter publication supabase_realtime add table tournament_teams;
  end if;
exception when undefined_object then null;   -- no publication in a scratch database
end $$;

commit;
