-- 021: tiebreak match for an exact points split.
-- When every match is finished and both teams have the same points, an admin can add one extra singles match
-- (match play, one player from each team). It is an ordinary matchup with no session, so cards, scoring and the
-- tail of compute_matchup_result work unchanged. The tournament goes back to 'active' until it finishes.
-- If the tiebreak itself is halved the totals are level again and another one can be added.
begin;

create or replace function admin_add_tiebreak(p_tournament uuid, p_user_a uuid, p_user_b uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  t tournaments%rowtype;
  last_m tournament_matchups%rowtype;
  tot_a numeric; tot_b numeric; open_count int; v_id uuid;
begin
  select * into t from tournaments where id = p_tournament for update;
  if not found then raise exception 'tournament not found'; end if;
  if auth.uid() is null or not is_tournament_admin(p_tournament) then raise exception 'admin only'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason required'; end if;

  select count(*) filter (where status <> 'complete'), coalesce(sum(points_team_a), 0), coalesce(sum(points_team_b), 0)
    into open_count, tot_a, tot_b from tournament_matchups where tournament_id = p_tournament;
  if not exists (select 1 from tournament_matchups where tournament_id = p_tournament) then
    raise exception 'there are no matches yet';
  end if;
  if open_count > 0 then raise exception 'finish the % unfinished matches first', open_count; end if;
  if tot_a <> tot_b then raise exception 'the points are not level (% to %)', tot_a, tot_b; end if;

  select * into last_m from tournament_matchups where tournament_id = p_tournament order by matchup_number desc limit 1;
  if not exists (select 1 from tournament_players where tournament_id = p_tournament and user_id = p_user_a
                    and team_id = last_m.team_a_id and invite_status = 'accepted') then
    raise exception 'player A must be on the first team';
  end if;
  if not exists (select 1 from tournament_players where tournament_id = p_tournament and user_id = p_user_b
                    and team_id = last_m.team_b_id and invite_status = 'accepted') then
    raise exception 'player B must be on the second team';
  end if;

  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, match_type, status)
  values (p_tournament, last_m.matchup_number + 1, last_m.team_a_id, last_m.team_b_id, array[p_user_a], array[p_user_b], 'match_play', 'pending')
  returning id into v_id;
  update tournaments set status = 'active', total_matches = total_matches + 1, updated_at = now() where id = p_tournament;

  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after, reason)
  values (p_tournament, auth.uid(), 'add_tiebreak', 'matchup', v_id,
          jsonb_build_object('status', t.status, 'points_a', tot_a, 'points_b', tot_b),
          jsonb_build_object('player_a', p_user_a, 'player_b', p_user_b), p_reason);
  return v_id;
end $$;

revoke execute on function admin_add_tiebreak(uuid, uuid, uuid, text) from public, anon;
grant execute on function admin_add_tiebreak(uuid, uuid, uuid, text) to authenticated;

commit;
