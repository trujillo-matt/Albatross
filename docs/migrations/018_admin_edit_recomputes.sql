-- 018: an admin score edit re-scores the match.
--
-- admin_set_hole_score changed the card but left the match result as it was, so an edit to a finished match was
-- not reflected on the board until someone pressed "Recompute result". It now recomputes the match itself, and when
-- that changes the result it writes a second audit entry with the old and new points, so the change is traceable to the edit.
-- compute_matchup_result ignores a match that is not ready (cards still being written), so editing a card in play is harmless.
begin;

create or replace function admin_set_hole_score(p_round uuid, p_hole int, p_strokes int, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tournament uuid;
  v_matchup uuid;
  v_before jsonb;
  v_old tournament_matchups%rowtype;
  v_new tournament_matchups%rowtype;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if p_hole not between 1 and 18 then raise exception 'hole must be 1 to 18'; end if;
  if p_strokes is not null and p_strokes not between 1 and 20 then raise exception 'strokes must be 1 to 20'; end if;

  select m.tournament_id, m.id, r.scores into v_tournament, v_matchup, v_before
    from rounds r
    join tournament_matchups m on m.id = r.matchup_id
   where r.id = p_round;
  if v_tournament is null then raise exception 'round is not part of a tournament'; end if;
  if not is_tournament_admin(v_tournament) then raise exception 'admin only'; end if;

  select * into v_old from tournament_matchups where id = v_matchup;

  update rounds
     set scores = jsonb_set(scores, array[(p_hole - 1)::text], coalesce(to_jsonb(p_strokes), 'null'::jsonb)),
         updated_at = now()
   where id = p_round;

  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after, reason)
  values (v_tournament, auth.uid(), 'edit_hole_score', 'round', p_round, v_before,
          (select scores from rounds where id = p_round), p_reason);

  perform compute_matchup_result(v_matchup);

  select * into v_new from tournament_matchups where id = v_matchup;
  if v_new.points_team_a is distinct from v_old.points_team_a or v_new.points_team_b is distinct from v_old.points_team_b
     or v_new.result is distinct from v_old.result then
    insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after, reason)
    values (v_tournament, auth.uid(), 'edit_changed_result', 'matchup', v_matchup,
            jsonb_build_object('result', v_old.result, 'points_team_a', v_old.points_team_a, 'points_team_b', v_old.points_team_b),
            jsonb_build_object('result', v_new.result, 'points_team_a', v_new.points_team_a, 'points_team_b', v_new.points_team_b),
            p_reason);
  end if;
end $$;

commit;
