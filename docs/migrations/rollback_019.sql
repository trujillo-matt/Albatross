-- Rollback for 019: no hand-set results. Refuses to run while any match carries an override, because dropping the
-- flag would let scoring overwrite it; clear those first with admin_clear_result.
begin;

do $$ begin
  if exists (select 1 from tournament_matchups where result_override) then
    raise exception 'matches still have results set by an admin; clear them first';
  end if;
end $$;

drop function if exists admin_set_result(uuid, numeric, numeric, text, text);
drop function if exists admin_clear_result(uuid, text);

create or replace function compute_matchup_result(p_matchup uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  t tournaments%rowtype;
  n_a int; n_b int;
  pa numeric; pb numeric;
  a_total int; b_total int;
  a_holes numeric := 0; b_holes numeric := 0;
  v_result text;
  tot_a numeric; tot_b numeric; all_done boolean; v_next uuid;
begin
  -- Row lock serializes concurrent finishers so the result is written once.
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then return; end if;
  select * into t from tournaments where id = m.tournament_id;

  create temporary table if not exists _mr (side text, round_id uuid, scores jsonb) on commit drop;
  truncate _mr;
  insert into _mr
  select case when l.user_id = any (m.team_a_player_ids) then 'A'
              when l.user_id = any (m.team_b_player_ids) then 'B' end,
         r.id, r.scores
    from tournament_matchup_rounds l
    join rounds r on r.id = l.round_id
   where l.matchup_id = p_matchup and r.status = 'completed';
  delete from _mr where side is null;

  select count(*) filter (where side = 'A'), count(*) filter (where side = 'B') into n_a, n_b from _mr;

  -- Ready check: scramble and alternate shot need one card per team; everything else, shamble included, needs one per paired player.
  if m.match_type in ('scramble', 'alternate_shot') then
    if n_a < 1 or n_b < 1 then return; end if;
  else
    if n_a + n_b < coalesce(array_length(m.team_a_player_ids, 1), 0) + coalesce(array_length(m.team_b_player_ids, 1), 0) then
      return;
    end if;
  end if;

  if m.match_type = 'match_play' then
    select coalesce(sum(case when a < b then 1 when a = b then 0.5 else 0 end), 0),
           coalesce(sum(case when b < a then 1 when a = b then 0.5 else 0 end), 0)
      into a_holes, b_holes
      from (select h,
                   (select min((s.scores ->> h)::int) from _mr s where s.side = 'A') a,
                   (select min((s.scores ->> h)::int) from _mr s where s.side = 'B') b
              from generate_series(0, 17) h) x
     where a is not null and b is not null;
    if a_holes > b_holes then pa := 1; pb := 0;
    elsif b_holes > a_holes then pa := 0; pb := 1;
    else pa := 0.5; pb := 0.5; end if;

  elsif m.match_type in ('best_ball', 'shamble', 'scramble', 'alternate_shot') then
    select coalesce(sum(a), 0), coalesce(sum(b), 0) into a_total, b_total
      from (select (select min((s.scores ->> h)::int) from _mr s where s.side = 'A') a,
                   (select min((s.scores ->> h)::int) from _mr s where s.side = 'B') b
              from generate_series(0, 17) h) x;
    -- Swift sums each side independently, skipping holes with no score for that side.
    if a_total < b_total then pa := 1; pb := 0;
    elsif b_total < a_total then pa := 0; pb := 1;
    else pa := 0.5; pb := 0.5; end if;

  else -- stroke_play: lowest single-player total per side
    select coalesce(min(tot) filter (where side = 'A'), 2147483647),
           coalesce(min(tot) filter (where side = 'B'), 2147483647)
      into a_total, b_total
      from (select side,
                   (select coalesce(sum((e.v)::int), 0)
                      from jsonb_array_elements_text(s.scores) with ordinality e(v, i)
                     where e.v is not null and e.v <> 'null') tot
              from _mr s) x;
    if a_total < b_total then pa := 1; pb := 0;
    elsif b_total < a_total then pa := 0; pb := 1;
    else pa := 0.5; pb := 0.5; end if;
  end if;

  v_result := case when pa > pb then 'team_a_win' when pb > pa then 'team_b_win' else 'tie' end;
  update tournament_matchups
     set status = 'complete', result = v_result, points_team_a = pa, points_team_b = pb
   where id = p_matchup;

  select coalesce(sum(points_team_a), 0), coalesce(sum(points_team_b), 0), bool_and(status = 'complete')
    into tot_a, tot_b, all_done
    from tournament_matchups where tournament_id = m.tournament_id;
  if tot_a >= t.points_to_win or tot_b >= t.points_to_win or all_done then
    update tournaments set status = 'complete', updated_at = now() where id = m.tournament_id;
  end if;
  -- When the last match of a session finishes, close it and open the next one with a fresh auto-filled lineup.
  if m.session_id is not null
     and not exists (select 1 from tournament_matchups where session_id = m.session_id and status <> 'complete') then
    update tournament_sessions set status = 'complete' where id = m.session_id;
    if (select status from tournaments where id = m.tournament_id) <> 'complete' then
      select n.id into v_next from tournament_sessions n, tournament_sessions c
       where c.id = m.session_id and n.tournament_id = c.tournament_id and n.status = 'pending'
         and (n.day_number, n.session_number) > (c.day_number, c.session_number)
       order by n.day_number, n.session_number limit 1;
      if v_next is not null then perform _autofill_session(v_next); end if;
    end if;
  end if;
end $$;

create or replace function admin_recompute_matchup(p_matchup uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_tournament uuid;
begin
  select tournament_id into v_tournament from tournament_matchups where id = p_matchup;
  if v_tournament is null or not is_tournament_admin(v_tournament) then raise exception 'admin only'; end if;
  perform compute_matchup_result(p_matchup);
  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id)
  values (v_tournament, auth.uid(), 'recompute_matchup', 'matchup', p_matchup);
end $$;

alter table tournament_matchups drop column if exists result_override;

commit;
