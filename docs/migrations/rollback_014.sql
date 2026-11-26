-- Rollback for 014: restores the previous grants and the previous set_hole_score.
begin;
grant all on profile_with_counts to anon, authenticated;
grant all on player_access_codes, code_redeem_attempts, tournament_audit_log to anon, authenticated;
alter function is_tournament_member(uuid) reset search_path;
alter function players_per_side(text) reset search_path;
alter function _team_ids(uuid) reset search_path;
alter function _presence_window() reset search_path;
grant execute on function handle_new_user() to public;
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
     );
  if not found then raise exception 'round not found, not yours, or already completed'; end if;
end $$;
commit;
