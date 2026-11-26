-- 014: security hardening found by the Supabase advisors and a manual audit on 2026-11-26.
--   1. profile_with_counts is a SECURITY DEFINER view that anon could read in full and that carried write grants.
--      It stays definer on purpose (user search and follower counts need to see profiles beyond RLS), but it is
--      now readable by signed-in users only and read-only.
--   2. Code, attempt and audit tables are reached only through functions and edge functions. Take them out of the
--      GraphQL schema by revoking the table privileges the clients never use.
--   3. Fix search_path on is_tournament_member and the three helper functions.
--   4. handle_new_user is a trigger function and needs no EXECUTE for clients.
--   5. set_hole_score refuses scores for a match whose session is not locked yet.
-- RLS helpers is_tournament_admin/creator and shares_tournament_with stay executable by anon (see 006).
begin;

revoke all on profile_with_counts from anon, authenticated;
grant select on profile_with_counts to authenticated;

revoke all on player_access_codes, code_redeem_attempts, tournament_audit_log from anon, authenticated;

alter function is_tournament_member(uuid) set search_path = public;
alter function players_per_side(text) set search_path = public;
alter function _team_ids(uuid) set search_path = public;
alter function _presence_window() set search_path = public;

revoke execute on function handle_new_user() from public, anon, authenticated;

create or replace function set_hole_score(p_round uuid, p_hole integer, p_strokes integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_hole not between 1 and 18 then raise exception 'hole must be 1 to 18'; end if;
  if p_strokes is not null and p_strokes not between 1 and 20 then
    raise exception 'strokes must be 1 to 20';
  end if;
  update rounds r
     set scores = jsonb_set(r.scores, array[(p_hole - 1)::text], coalesce(to_jsonb(p_strokes), 'null'::jsonb)),
         updated_at = now()
   where r.id = p_round and r.status = 'in_progress'
     and (
       (r.user_id = auth.uid() and (matchup_scorer(r.matchup_id) is null or matchup_scorer(r.matchup_id) = auth.uid()))
       or (r.matchup_id is not null and matchup_scorer(r.matchup_id) = auth.uid())
     )
     and not exists (
       select 1 from tournament_matchups m join tournament_sessions s on s.id = m.session_id
        where m.id = r.matchup_id and s.status not in ('locked', 'complete')
     );
  if not found then raise exception 'round not found, not yours, not open for scoring yet, or already completed'; end if;
end $$;

commit;
