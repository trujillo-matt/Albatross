-- 011: both captains on the callouts page.
-- Each captain's screen checks in every few seconds while the callouts page is open (callout_checkin).
-- make_callout and pass_callout refuse unless both captains checked in recently, so a pick only goes live
-- when both are there. An admin using the override still bypasses it.

begin;

create table if not exists callout_presence (
  session_id uuid not null references tournament_sessions(id) on delete cascade,
  user_id    uuid not null,
  seen_at    timestamptz not null default now(),
  primary key (session_id, user_id)
);
alter table callout_presence enable row level security;
revoke all on callout_presence from anon, authenticated;   -- read and written only through the functions below

-- How recently a captain must have checked in to count as present.
create or replace function _presence_window() returns interval language sql immutable as $$ select interval '20 seconds' $$;

-- A captain (or admin) checks in. Returns who is here now: one row per team captain.
create or replace function callout_checkin(p_session uuid)
returns table (team_id uuid, captain_user_id uuid, present boolean)
language plpgsql security definer set search_path = public as $$
declare s tournament_sessions%rowtype;
begin
  select * into s from tournament_sessions where id = p_session;
  if not found then raise exception 'session not found'; end if;
  if auth.uid() is null or not (
       is_tournament_admin(s.tournament_id)
       or exists (select 1 from tournament_teams t where t.tournament_id = s.tournament_id and t.captain_user_id = auth.uid())
     ) then
    raise exception 'only a captain or an admin can check in';
  end if;
  insert into callout_presence (session_id, user_id, seen_at) values (p_session, auth.uid(), now())
  on conflict (session_id, user_id) do update set seen_at = excluded.seen_at;
  return query
    select t.id, t.captain_user_id,
           coalesce((select cp.seen_at > now() - _presence_window() from callout_presence cp
                      where cp.session_id = p_session and cp.user_id = t.captain_user_id), false)
      from tournament_teams t where t.tournament_id = s.tournament_id order by t.side;
end $$;

-- True when every team has a captain and each of them is on the page.
create or replace function callouts_ready(p_session uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select count(*) >= 2 and bool_and(t.captain_user_id is not null and exists (
             select 1 from callout_presence cp
              where cp.session_id = p_session and cp.user_id = t.captain_user_id and cp.seen_at > now() - _presence_window()))
      from tournament_sessions s join tournament_teams t on t.tournament_id = s.tournament_id
     where s.id = p_session), false);
$$;

revoke execute on function callout_checkin(uuid) from public, anon;
grant execute on function callout_checkin(uuid) to authenticated;
revoke execute on function callouts_ready(uuid) from public, anon;
grant execute on function callouts_ready(uuid) to authenticated;
revoke execute on function _presence_window() from public, anon, authenticated;

create or replace function make_callout(p_session uuid, p_my_unit uuid[], p_their_unit uuid[], p_override boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  s tournament_sessions%rowtype; ta uuid; tb uuid; me_a boolean; mine tournament_matchups%rowtype; theirs tournament_matchups%rowtype;
  mine_unit uuid[]; theirs_mine uuid[]; open_left int; last_id uuid;
begin
  select * into s from tournament_sessions where id = p_session for update;
  if not found then raise exception 'session not found'; end if;
  if s.status <> 'callouts' then raise exception 'callouts are not open'; end if;
  if not (exists (select 1 from tournament_teams where id = s.turn_team_id and captain_user_id = auth.uid())
          or (p_override and is_tournament_admin(s.tournament_id))) then
    raise exception 'not your turn';
  end if;
  if not p_override and not callouts_ready(p_session) then
    raise exception 'both captains need to be on the callouts page';
  end if;
  select team_a, team_b into ta, tb from _team_ids(s.tournament_id);
  me_a := s.turn_team_id = ta;

  select * into mine from tournament_matchups where session_id = p_session and called_at is null
     and (case when me_a then team_a_player_ids else team_b_player_ids end) @> p_my_unit
     and (case when me_a then team_a_player_ids else team_b_player_ids end) <@ p_my_unit;
  if not found then raise exception 'that unit is not available'; end if;
  select * into theirs from tournament_matchups where session_id = p_session and called_at is null
     and (case when me_a then team_b_player_ids else team_a_player_ids end) @> p_their_unit
     and (case when me_a then team_b_player_ids else team_a_player_ids end) <@ p_their_unit;
  if not found then raise exception 'that opponent is not available'; end if;

  if mine.id <> theirs.id then
    theirs_mine := case when me_a then theirs.team_a_player_ids else theirs.team_b_player_ids end;
    mine_unit := case when me_a then mine.team_a_player_ids else mine.team_b_player_ids end;
    if me_a then
      update tournament_matchups set team_a_player_ids = theirs_mine, updated_at = now() where id = mine.id;
      update tournament_matchups set team_a_player_ids = mine_unit, updated_at = now() where id = theirs.id;
    else
      update tournament_matchups set team_b_player_ids = theirs_mine, updated_at = now() where id = mine.id;
      update tournament_matchups set team_b_player_ids = mine_unit, updated_at = now() where id = theirs.id;
    end if;
  end if;
  update tournament_matchups set called_by_team_id = s.turn_team_id, called_at = now() where id = theirs.id;

  select count(*), min(id::text)::uuid into open_left, last_id from tournament_matchups where session_id = p_session and called_at is null;
  if open_left <= 1 then
    perform _lock_session(p_session);      -- the last match has no choice left
  else
    update tournament_sessions set turn_team_id = case when me_a then tb else ta end, consecutive_passes = 0 where id = p_session;
  end if;
end $$;

create or replace function pass_callout(p_session uuid, p_override boolean default false) returns void language plpgsql security definer set search_path = public as $$
declare s tournament_sessions%rowtype; ta uuid; tb uuid;
begin
  select * into s from tournament_sessions where id = p_session for update;
  if not found then raise exception 'session not found'; end if;
  if s.status <> 'callouts' then raise exception 'callouts are not open'; end if;
  if not (exists (select 1 from tournament_teams where id = s.turn_team_id and captain_user_id = auth.uid())
          or (p_override and is_tournament_admin(s.tournament_id))) then
    raise exception 'not your turn';
  end if;
  if not p_override and not callouts_ready(p_session) then
    raise exception 'both captains need to be on the callouts page';
  end if;
  select team_a, team_b into ta, tb from _team_ids(s.tournament_id);
  if s.consecutive_passes + 1 >= 2 then
    perform _lock_session(p_session);
  else
    update tournament_sessions set consecutive_passes = consecutive_passes + 1,
           turn_team_id = case when turn_team_id = ta then tb else ta end where id = p_session;
  end if;
end $$;

commit;
