-- Rollback for 018: an admin score edit no longer re-scores the match (use Recompute result).
begin;
create or replace function admin_set_hole_score(p_round uuid, p_hole int, p_strokes int, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tournament uuid;
  v_before jsonb;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if p_hole not between 1 and 18 then raise exception 'hole must be 1 to 18'; end if;
  if p_strokes is not null and p_strokes not between 1 and 20 then raise exception 'strokes must be 1 to 20'; end if;

  select m.tournament_id, r.scores into v_tournament, v_before
    from rounds r
    join tournament_matchups m on m.id = r.matchup_id
   where r.id = p_round;
  if v_tournament is null then raise exception 'round is not part of a tournament'; end if;
  if not is_tournament_admin(v_tournament) then raise exception 'admin only'; end if;

  update rounds
     set scores = jsonb_set(scores, array[(p_hole - 1)::text], coalesce(to_jsonb(p_strokes), 'null'::jsonb)),
         updated_at = now()
   where id = p_round;

  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after, reason)
  values (v_tournament, auth.uid(), 'edit_hole_score', 'round', p_round, v_before,
          (select scores from rounds where id = p_round), p_reason);
end $$;

commit;
