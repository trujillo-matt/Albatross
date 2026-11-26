-- 019: an admin can set a match result by hand (forfeit, no-show, rainout).
--
-- admin_set_result records the points, marks the match complete and sets result_override so scoring never overwrites it
-- (a late card, or a score edit, leaves it alone). Everything that follows a finished match still runs: the tournament
-- completes when a team reaches the points to win, and the session closes and opens the next one. admin_clear_result
-- undoes it: the match goes back to being scored from its cards. Both write the audit log with the reason given.
-- Known limit: clearing an override does not reopen a tournament that the override had already completed.
begin;

alter table tournament_matchups add column if not exists result_override boolean not null default false;

-- compute_matchup_result is the 017 version with one change: a match with result_override keeps its points and skips scoring.
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

  -- A result an admin set by hand (forfeit, no-show, rainout) stands: scoring is skipped, but the rest still runs
  -- (tournament completion, closing the session, opening the next one).
  if m.result_override then
    pa := m.points_team_a; pb := m.points_team_b;
  else
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

create or replace function admin_set_result(p_matchup uuid, p_points_a numeric, p_points_b numeric, p_kind text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
begin
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'match not found'; end if;
  if auth.uid() is null or not is_tournament_admin(m.tournament_id) then raise exception 'admin only'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if p_kind is null or p_kind not in ('forfeit', 'no_show', 'rainout', 'other') then
    raise exception 'kind must be forfeit, no_show, rainout or other';
  end if;
  if p_points_a is null or p_points_b is null or p_points_a not in (0, 0.5, 1) or p_points_b not in (0, 0.5, 1) then
    raise exception 'points must be 0, 0.5 or 1 for each team';
  end if;
  if p_points_a + p_points_b > 1 then raise exception 'a match is worth 1 point in total'; end if;

  update tournament_matchups
     set result_override = true, status = 'complete', points_team_a = p_points_a, points_team_b = p_points_b,
         result = case when p_points_a > p_points_b then 'team_a_win' when p_points_b > p_points_a then 'team_b_win' else 'tie' end,
         updated_at = now()
   where id = p_matchup;

  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after, reason)
  values (m.tournament_id, auth.uid(), 'set_result', 'matchup', p_matchup,
          jsonb_build_object('status', m.status, 'result', m.result, 'points_team_a', m.points_team_a, 'points_team_b', m.points_team_b, 'override', m.result_override),
          jsonb_build_object('kind', p_kind, 'points_team_a', p_points_a, 'points_team_b', p_points_b),
          p_reason);

  perform compute_matchup_result(p_matchup);   -- tournament completion and the session roll-over
end $$;

create or replace function admin_clear_result(p_matchup uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
begin
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'match not found'; end if;
  if auth.uid() is null or not is_tournament_admin(m.tournament_id) then raise exception 'admin only'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if not m.result_override then raise exception 'this result was not set by an admin'; end if;

  update tournament_matchups
     set result_override = false, result = null, points_team_a = 0, points_team_b = 0,
         status = case when coalesce(array_length(team_a_player_ids, 1), 0) > 0 then 'active' else 'pending' end,
         updated_at = now()
   where id = p_matchup;

  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after, reason)
  values (m.tournament_id, auth.uid(), 'clear_result', 'matchup', p_matchup,
          jsonb_build_object('result', m.result, 'points_team_a', m.points_team_a, 'points_team_b', m.points_team_b),
          jsonb_build_object('status', (select status from tournament_matchups where id = p_matchup)), p_reason);

  perform compute_matchup_result(p_matchup);   -- scores it from its cards again if they are all in
end $$;

-- A stale recompute must not look like it did something while an override stands.
create or replace function admin_recompute_matchup(p_matchup uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_tournament uuid;
begin
  select tournament_id into v_tournament from tournament_matchups where id = p_matchup;
  if v_tournament is null or not is_tournament_admin(v_tournament) then raise exception 'admin only'; end if;
  if exists (select 1 from tournament_matchups where id = p_matchup and result_override) then
    raise exception 'the result was set by an admin; clear it first';
  end if;
  perform compute_matchup_result(p_matchup);
  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id)
  values (v_tournament, auth.uid(), 'recompute_matchup', 'matchup', p_matchup);
end $$;

revoke execute on function admin_set_result(uuid, numeric, numeric, text, text), admin_clear_result(uuid, text) from public, anon;
grant execute on function admin_set_result(uuid, numeric, numeric, text, text), admin_clear_result(uuid, text) to authenticated;

commit;
