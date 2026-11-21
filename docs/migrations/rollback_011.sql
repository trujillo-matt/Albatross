-- Rollback for 011: callouts no longer need both captains present.
begin;
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
  select team_a, team_b into ta, tb from _team_ids(s.tournament_id);
  if s.consecutive_passes + 1 >= 2 then
    perform _lock_session(p_session);
  else
    update tournament_sessions set consecutive_passes = consecutive_passes + 1,
           turn_team_id = case when turn_team_id = ta then tb else ta end where id = p_session;
  end if;
end $$;

drop function if exists callouts_ready(uuid);
drop function if exists callout_checkin(uuid);
drop function if exists _presence_window();
drop table if exists callout_presence;
commit;
