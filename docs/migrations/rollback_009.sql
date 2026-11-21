-- Reverses 009. Restores set_hole_score to its migration-002 body.
begin;
drop trigger if exists rounds_scorer_guard on rounds;
drop function if exists rounds_scorer_guard();
drop function if exists finish_group_scoring(uuid);
drop function if exists start_group_scoring(uuid, jsonb);
drop function if exists set_scorer(uuid, uuid);
create or replace function set_hole_score(p_round uuid, p_hole int, p_strokes int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_hole not between 1 and 18 then raise exception 'hole must be 1 to 18'; end if;
  if p_strokes is not null and p_strokes not between 1 and 20 then raise exception 'strokes must be 1 to 20'; end if;
  update rounds
     set scores = jsonb_set(scores, array[(p_hole - 1)::text], coalesce(to_jsonb(p_strokes), 'null'::jsonb)),
         updated_at = now()
   where id = p_round and user_id = auth.uid() and status = 'in_progress';
  if not found then raise exception 'round not found, not yours, or already completed'; end if;
end $$;
drop function if exists matchup_scorer(uuid);
-- Scorer assignments already saved in tournament_matchups.scorer_user_id are left in place (the column predates 009).
commit;
