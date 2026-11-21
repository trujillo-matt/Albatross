-- 012: one person keeps score for the whole foursome.
--
-- A foursome is the players who play together. In pairs formats a match already has four players, so a foursome is
-- one match. In singles formats (match play, stroke play) a match has two players, so a session's matches are played
-- two at a time, in match order: 1 and 2, 3 and 4, and so on. A scorer keeps the cards for everyone in the foursome,
-- across both matches, and submits them together. Setting a scorer sets it on every match in the foursome.
begin;

create or replace function foursome_of(p_matchup uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  with me as (select id, session_id, match_type from tournament_matchups where id = p_matchup),
  ranked as (
    select m.id, (row_number() over (partition by m.session_id order by m.matchup_number) - 1) / 2 as grp
      from tournament_matchups m, me
     where me.session_id is not null and me.match_type in ('match_play', 'stroke_play') and m.session_id = me.session_id
  )
  select id from ranked where grp = (select grp from ranked where id = p_matchup)
  union all
  select p_matchup where not exists (
    select 1 from me where session_id is not null and match_type in ('match_play', 'stroke_play'))
$$;

create or replace function set_scorer(p_matchup uuid, p_scorer uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  me uuid := auth.uid();
  is_adm boolean;
  i_play boolean;
  mates uuid[];
  players uuid[];
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  if m.status = 'pending' then raise exception 'pairings are not set yet'; end if;
  if m.status = 'complete' then raise exception 'match is already complete'; end if;

  select array_agg(x) into mates from foursome_of(p_matchup) x;
  perform 1 from tournament_matchups where id = any (mates) for update;
  select coalesce(array_agg(distinct p), '{}') into players
    from tournament_matchups t, unnest(t.team_a_player_ids || t.team_b_player_ids) p where t.id = any (mates);

  is_adm := is_tournament_admin(m.tournament_id);
  i_play := me = any (players);

  if not is_adm and not i_play then raise exception 'only players in this foursome can keep score'; end if;
  if p_scorer is not null and not (p_scorer = any (players)) then
    raise exception 'the scorer must be playing in this foursome';
  end if;

  if not is_adm then
    if p_scorer is not null then
      if p_scorer <> me then raise exception 'you can only volunteer yourself'; end if;
      if m.scorer_user_id is not null and m.scorer_user_id <> me then raise exception 'someone is already keeping score'; end if;
    elsif m.scorer_user_id is distinct from me then
      raise exception 'only the current scorer can step down';
    end if;
  end if;

  update tournament_matchups set scorer_user_id = p_scorer, updated_at = now() where id = any (mates);
  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after)
  values (m.tournament_id, me, 'set_scorer', 'matchup', p_matchup, to_jsonb(m.scorer_user_id), to_jsonb(p_scorer));
end $$;

-- Creates the foursome's cards (idempotent): one per player, or one per side in scramble and alternate shot.
-- Returns every card in the foursome, with the match each belongs to.
drop function if exists start_group_scoring(uuid, jsonb);
create or replace function start_group_scoring(p_matchup uuid, p_course jsonb default '{}'::jsonb)
returns table (out_round uuid, out_owner uuid, out_side text, out_matchup uuid)
language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  mm tournament_matchups%rowtype;
  me uuid := auth.uid();
  mates uuid[];
  owners uuid[];
  o uuid;
  rid uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  select array_agg(x) into mates from foursome_of(p_matchup) x;
  if exists (select 1 from tournament_matchups where id = any (mates) and status <> 'active') then
    raise exception 'every match in the foursome has to be open for scoring';
  end if;
  if not (m.scorer_user_id = me or is_tournament_admin(m.tournament_id)) then
    raise exception 'only the scorer can start the group scorecards';
  end if;

  for mm in select * from tournament_matchups where id = any (mates) order by matchup_number loop
    if mm.match_type in ('scramble', 'alternate_shot') then
      owners := array_remove(array[mm.team_a_player_ids[1], mm.team_b_player_ids[1]], null);
    else
      owners := mm.team_a_player_ids || mm.team_b_player_ids;
    end if;
    if coalesce(array_length(owners, 1), 0) = 0 then raise exception 'no players are paired for match %', mm.matchup_number; end if;

    foreach o in array owners loop
      select id into rid from rounds where matchup_id = mm.id and user_id = o limit 1;
      if rid is null then
        rid := gen_random_uuid();
        insert into rounds (id, user_id, course_name, course_id, course_pars, course_handicaps, course_yardages,
                            course_rating, slope_rating, date, scores, status, matchup_id)
        values (rid, o, coalesce(nullif(p_course->>'course_name', ''), 'Tournament Match'), nullif(p_course->>'course_id', ''),
                nullif(p_course->'pars', 'null'::jsonb), nullif(p_course->'handicaps', 'null'::jsonb), nullif(p_course->'yardages', 'null'::jsonb),
                nullif(p_course->>'rating', '')::numeric, nullif(p_course->>'slope', '')::int,
                now(), to_jsonb(array_fill(null::int, array[18])), 'in_progress', mm.id);
      end if;
      insert into tournament_matchup_rounds (matchup_id, round_id, user_id) values (mm.id, rid, o)
        on conflict (matchup_id, user_id) do nothing;
    end loop;
  end loop;

  return query
    select r.id, r.user_id, case when r.user_id = any (t.team_a_player_ids) then 'A' else 'B' end, t.id
      from tournament_matchups t join rounds r on r.matchup_id = t.id
     where t.id = any (mates)
       and r.user_id = any (case when t.match_type in ('scramble', 'alternate_shot')
                                 then array_remove(array[t.team_a_player_ids[1], t.team_b_player_ids[1]], null)
                                 else t.team_a_player_ids || t.team_b_player_ids end)
     order by t.matchup_number, 3, 2;
end $$;

-- Submits every card in the foursome at once, once every card has 18 holes.
create or replace function finish_group_scoring(p_matchup uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  me uuid := auth.uid();
  mates uuid[];
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  select array_agg(x) into mates from foursome_of(p_matchup) x;
  if exists (select 1 from tournament_matchups where id = any (mates) and status <> 'active') then
    raise exception 'the match is not open for scoring';
  end if;
  if not (m.scorer_user_id = me or is_tournament_admin(m.tournament_id)) then
    raise exception 'only the scorer can submit the group scorecards';
  end if;
  if exists (select 1 from tournament_matchups t where t.id = any (mates)
               and not exists (select 1 from rounds r where r.matchup_id = t.id)) then
    raise exception 'no scorecards have been started';
  end if;
  if exists (select 1 from rounds r where r.matchup_id = any (mates) and r.status = 'in_progress'
               and exists (select 1 from jsonb_array_elements(r.scores) e where e = 'null'::jsonb)) then
    raise exception 'every scorecard needs all 18 holes';
  end if;
  -- The existing trigger computes each match's result once its last card completes.
  update rounds set status = 'completed', updated_at = now() where matchup_id = any (mates) and status = 'in_progress';
end $$;

revoke execute on function foursome_of(uuid), set_scorer(uuid, uuid), start_group_scoring(uuid, jsonb),
  finish_group_scoring(uuid) from public, anon;
grant execute on function foursome_of(uuid), set_scorer(uuid, uuid), start_group_scoring(uuid, jsonb),
  finish_group_scoring(uuid) to authenticated;

commit;
