-- Rolls back 008. Restore compute_matchup_result and set_pairings from 002 and 005 afterwards.
begin;
drop function if exists make_callout(uuid, uuid[], uuid[], boolean), pass_callout(uuid, boolean), open_callouts(uuid, uuid),
  set_session_side(uuid, uuid, jsonb), autofill_session(uuid), start_tournament(uuid), _autofill_session(uuid), _lock_session(uuid),
  _can_manage_team(uuid, uuid), _team_ids(uuid), players_per_side(text);
alter table tournament_matchups drop column if exists called_at, drop column if exists called_by_team_id, drop column if exists session_id;
drop table if exists tournament_sessions;
commit;
