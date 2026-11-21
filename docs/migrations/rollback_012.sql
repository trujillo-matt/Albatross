-- Rollback for 012: scoring goes back to one match at a time.
begin;
create or replace function set_scorer(p_matchup uuid, p_scorer uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  me uuid := auth.uid();
  is_adm boolean;
  i_play boolean;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  if m.status = 'pending' then raise exception 'pairings are not set yet'; end if;
  if m.status = 'complete' then raise exception 'match is already complete'; end if;

  is_adm := is_tournament_admin(m.tournament_id);
  i_play := me = any (m.team_a_player_ids) or me = any (m.team_b_player_ids);

  if not is_adm and not i_play then raise exception 'only players in this match can keep score'; end if;
  if p_scorer is not null and not (p_scorer = any (m.team_a_player_ids) or p_scorer = any (m.team_b_player_ids)) then
    raise exception 'the scorer must be playing in this match';
  end if;

  if not is_adm then
    if p_scorer is not null then
      if p_scorer <> me then raise exception 'you can only volunteer yourself'; end if;
      if m.scorer_user_id is not null and m.scorer_user_id <> me then raise exception 'someone is already keeping score'; end if;
    elsif m.scorer_user_id is distinct from me then
      raise exception 'only the current scorer can step down';
    end if;
  end if;

  update tournament_matchups set scorer_user_id = p_scorer, updated_at = now() where id = p_matchup;
  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after)
  values (m.tournament_id, me, 'set_scorer', 'matchup', p_matchup, to_jsonb(m.scorer_user_id), to_jsonb(p_scorer));
end $$;

drop function if exists start_group_scoring(uuid, jsonb);
create or replace function start_group_scoring(p_matchup uuid, p_course jsonb default '{}'::jsonb)
returns table (out_round uuid, out_owner uuid, out_side text)
language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  me uuid := auth.uid();
  owners uuid[];
  o uuid;
  rid uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  if m.status <> 'active' then raise exception 'the match is not open for scoring'; end if;
  if not (m.scorer_user_id = me or is_tournament_admin(m.tournament_id)) then
    raise exception 'only the scorer can start the group scorecards';
  end if;

  if m.match_type in ('scramble', 'alternate_shot') then
    owners := array_remove(array[m.team_a_player_ids[1], m.team_b_player_ids[1]], null);
  else
    owners := m.team_a_player_ids || m.team_b_player_ids;
  end if;
  if coalesce(array_length(owners, 1), 0) = 0 then raise exception 'no players are paired for this match'; end if;

  foreach o in array owners loop
    select id into rid from rounds where matchup_id = p_matchup and user_id = o limit 1;
    if rid is null then
      rid := gen_random_uuid();
      insert into rounds (id, user_id, course_name, course_id, course_pars, course_handicaps, course_yardages,
                          course_rating, slope_rating, date, scores, status, matchup_id)
      values (rid, o, coalesce(nullif(p_course->>'course_name', ''), 'Tournament Match'), nullif(p_course->>'course_id', ''),
              nullif(p_course->'pars', 'null'::jsonb), nullif(p_course->'handicaps', 'null'::jsonb), nullif(p_course->'yardages', 'null'::jsonb),
              nullif(p_course->>'rating', '')::numeric, nullif(p_course->>'slope', '')::int,
              now(), to_jsonb(array_fill(null::int, array[18])), 'in_progress', p_matchup);
    end if;
    insert into tournament_matchup_rounds (matchup_id, round_id, user_id) values (p_matchup, rid, o)
      on conflict (matchup_id, user_id) do nothing;
  end loop;

  return query
    select r.id, r.user_id, case when r.user_id = any (m.team_a_player_ids) then 'A' else 'B' end
      from rounds r where r.matchup_id = p_matchup and r.user_id = any (owners)
     order by 3, 2;
end $$;

create or replace function finish_group_scoring(p_matchup uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  if m.status <> 'active' then raise exception 'the match is not open for scoring'; end if;
  if not (m.scorer_user_id = me or is_tournament_admin(m.tournament_id)) then
    raise exception 'only the scorer can submit the group scorecards';
  end if;
  if not exists (select 1 from rounds where matchup_id = p_matchup) then raise exception 'no scorecards have been started'; end if;
  if exists (select 1 from rounds r where r.matchup_id = p_matchup and r.status = 'in_progress'
               and exists (select 1 from jsonb_array_elements(r.scores) e where e = 'null'::jsonb)) then
    raise exception 'every scorecard needs all 18 holes';
  end if;
  -- The existing trigger computes the result once the last card completes.
  update rounds set status = 'completed', updated_at = now() where matchup_id = p_matchup and status = 'in_progress';
end $$;

drop function if exists foursome_of(uuid);
revoke execute on function set_scorer(uuid, uuid), start_group_scoring(uuid, jsonb), finish_group_scoring(uuid) from public, anon;
grant execute on function set_scorer(uuid, uuid), start_group_scoring(uuid, jsonb), finish_group_scoring(uuid) to authenticated;
commit;
