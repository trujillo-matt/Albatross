-- Least-privilege EXECUTE on the functions added by 002 to 005. Postgres grants EXECUTE to PUBLIC by default, so
-- before this every function was callable by signed-out clients. Each one rejects anonymous callers internally;
-- this removes the ability to call them at all.
--   * RPC functions: signed-in users only (get_public_standings stays open to anon on purpose).
--   * Trigger functions: nobody calls them directly; triggers fire regardless of EXECUTE.
--   * RLS helpers (is_tournament_admin/creator, shares_tournament_with) stay executable by anon and authenticated:
--     policies call them as the querying role, so removing it would make signed-out reads error instead of
--     returning nothing.
begin;

revoke execute on function
  cast_captain_votes(uuid, uuid[]), finalize_captains(uuid, uuid[]), draft_pick(uuid, uuid, boolean),
  set_hole_score(uuid, int, int), set_pairings(uuid, uuid[], uuid[]), set_spectator_link(uuid, boolean),
  admin_code_status(uuid), admin_set_hole_score(uuid, int, int, text), admin_recompute_matchup(uuid), admin_audit_log(uuid)
  from public, anon;
grant execute on function
  cast_captain_votes(uuid, uuid[]), finalize_captains(uuid, uuid[]), draft_pick(uuid, uuid, boolean),
  set_hole_score(uuid, int, int), set_pairings(uuid, uuid[], uuid[]), set_spectator_link(uuid, boolean),
  admin_code_status(uuid), admin_set_hole_score(uuid, int, int, text), admin_recompute_matchup(uuid), admin_audit_log(uuid)
  to authenticated;

revoke execute on function trg_round_completed(), trg_matchup_round_linked(), tp_guard_update()
  from public, anon, authenticated;

commit;
