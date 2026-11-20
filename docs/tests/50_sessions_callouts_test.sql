-- Tests for migration 008: sessions, roster-sized matches, sit-outs, captain callouts. Uses helpers from 10_rules_test.sql.
create function t.finish_match(p_m uuid, p_a int, p_b int) returns void language plpgsql as $$
declare m tournament_matchups%rowtype; u uuid; r uuid;
begin
  select * into m from tournament_matchups where id = p_m;
  foreach u in array m.team_a_player_ids || m.team_b_player_ids loop
    r := gen_random_uuid();
    insert into rounds (id, user_id, course_name, date, scores, status, matchup_id)
      values (r, u, 'C', now(), (select jsonb_agg(case when u = any (m.team_a_player_ids) then p_a else p_b end) from generate_series(1, 18)), 'completed', p_m);
    insert into tournament_matchup_rounds (matchup_id, round_id, user_id) values (p_m, r, u);
  end loop;
end $$;

-- teamA: users listed, teamB: users listed; draft_position follows list order. Captains are the first of each list.
create function t.sessions_fixture(a int[], b int[], formats text[]) returns uuid language plpgsql as $$
declare v uuid; ta uuid; tb uuid; i int; k int;
begin
  insert into tournaments (name, creator_user_id, status, match_type) values ('S', t.u(1), 'draft', 'best_ball') returning id into v;
  insert into tournament_teams (tournament_id, name, side, captain_user_id) values (v, 'A', 'A', t.u(a[1])) returning id into ta;
  insert into tournament_teams (tournament_id, name, side, captain_user_id) values (v, 'B', 'B', t.u(b[1])) returning id into tb;
  insert into tournament_players (tournament_id, user_id, invite_status, is_admin, team_id, draft_position)
    select v, t.u(a[g.n]), 'accepted', a[g.n] = 1, ta, g.n from generate_series(1, array_length(a, 1)) g(n);
  insert into tournament_players (tournament_id, user_id, invite_status, team_id, draft_position)
    select v, t.u(b[g.n]), 'accepted', tb, g.n from generate_series(1, array_length(b, 1)) g(n);
  for i in 1..array_length(formats, 1) loop
    insert into tournament_sessions (tournament_id, day_number, session_number, match_type)
      values (v, (i + 1) / 2, 2 - i % 2, formats[i]);   -- sessions 1,2 are day 1; 3,4 are day 2
  end loop;
  return v;
end $$;

-- ---------------------------------------------------------------- match counts come from the roster
do $$ declare v uuid; v2 uuid; begin
  -- 4 v 4: pairs make 2 matches, singles make 4, alternate shot 2
  v := t.sessions_fixture(array[1,2,3,4], array[5,6,7,8], array['best_ball','match_play','alternate_shot']);
  perform t.as_user(5);
  perform t.expect_error(format('select start_tournament(%L)', v), 'only an admin');
  perform t.as_user(1);
  perform start_tournament(v);
  perform t.assert((select array_agg(match_count order by day_number, session_number) from tournament_sessions where tournament_id = v) = array[2,4,2], 'match counts 2,4,2');
  perform t.assert((select count(*) from tournament_matchups where tournament_id = v) = 8, '8 matches created');
  perform t.assert((select total_matches from tournaments where id = v) = 8 and (select points_to_win from tournaments where id = v) = 4.5, 'points to win 4.5 of 8');
  perform t.assert((select status from tournament_sessions where tournament_id = v and day_number = 1 and session_number = 1) = 'lineup', 'first session is in lineup');
  perform t.assert((select count(*) from tournament_sessions where tournament_id = v and status = 'pending') = 2, 'later sessions pending');
  perform t.assert((select bool_and(array_length(team_a_player_ids, 1) = 2 and array_length(team_b_player_ids, 1) = 2)
                      from tournament_matchups m join tournament_sessions s on s.id = m.session_id where s.session_number = 1 and s.day_number = 1), 'lineup auto-filled with pairs');
  perform t.assert((select bool_and(status = 'pending') from tournament_matchups where tournament_id = v), 'nothing playable before callouts lock');
  perform t.expect_error(format('select start_tournament(%L)', v), 'draft stage');

  -- uneven rosters: 4 v 3 pairs -> floor(3/2) = 1 match, extras sit out
  v2 := t.sessions_fixture(array[1,2,3,4], array[5,6,7], array['best_ball']);
  perform t.as_user(1);
  perform start_tournament(v2);
  perform t.assert((select match_count from tournament_sessions where tournament_id = v2) = 1, '4v3 pairs -> 1 match');
  perform t.assert((select array_length(team_a_player_ids, 1) from tournament_matchups where tournament_id = v2) = 2, 'pair on side A');
  -- a one-match session has nothing to call out, so it locks as soon as callouts open
  perform open_callouts((select id from tournament_sessions where tournament_id = v2));
  perform t.assert((select status from tournament_sessions where tournament_id = v2) = 'locked', 'single-match session locks at once');
  perform t.assert((select status from tournament_matchups where tournament_id = v2) = 'active', 'its match is playable');
  -- not enough players for the format
  perform t.expect_error(format('select start_tournament(%L)', t.sessions_fixture(array[1], array[5], array['best_ball'])), 'at least 2 players');
end $$;

-- ---------------------------------------------------------------- callouts, swap rule, session rollover
do $$ declare v uuid; s1 uuid; s2 uuid; ta uuid; tb uuid; m1 tournament_matchups%rowtype; m2 tournament_matchups%rowtype;
              a1 uuid[]; a2 uuid[]; b1 uuid[]; mm record; begin
  select id into v from tournaments where name = 'S' order by created_at limit 1;
  select team_a, team_b into ta, tb from _team_ids(v);
  select id into s1 from tournament_sessions where tournament_id = v and day_number = 1 and session_number = 1;
  select id into s2 from tournament_sessions where tournament_id = v and day_number = 1 and session_number = 2;

  -- captains can rearrange only their own side, only in lineup
  perform t.as_user(5);
  perform t.expect_error(format('select set_session_side(%L, %L, ''[[1,2]]'')', s1, ta), 'admin or that team');
  perform t.as_user(1);
  select team_a_player_ids, team_b_player_ids into a1, b1 from tournament_matchups where session_id = s1 order by matchup_number limit 1;
  select team_a_player_ids into a2 from tournament_matchups where session_id = s1 order by matchup_number offset 1 limit 1;
  perform set_session_side(s1, ta, jsonb_build_array(to_jsonb(a2), to_jsonb(a1)));      -- swap the two pairs
  perform t.assert((select team_a_player_ids from tournament_matchups where session_id = s1 order by matchup_number limit 1) = a2, 'captain A reordered own side');
  perform t.assert((select team_b_player_ids from tournament_matchups where session_id = s1 order by matchup_number limit 1) = b1, 'side B untouched');
  perform t.expect_error(format('select set_session_side(%L, %L, %L)', s1, ta, jsonb_build_array(to_jsonb(a1), to_jsonb(a1))), 'distinct');
  perform t.expect_error(format('select make_callout(%L, %L, %L)', s1, a1, b1), 'not open');

  -- level at 0-0 and first session: team A calls first
  perform open_callouts(s1);
  perform t.assert((select turn_team_id from tournament_sessions where id = s1) = ta, 'team A calls first');
  select * into m1 from tournament_matchups where session_id = s1 order by matchup_number limit 1;
  select * into m2 from tournament_matchups where session_id = s1 order by matchup_number offset 1 limit 1;
  perform t.as_user(5);
  perform t.expect_error(format('select make_callout(%L, %L, %L)', s1, m1.team_b_player_ids, m1.team_a_player_ids), 'not your turn');
  perform t.expect_error(format('select set_pairings(%L, %L, %L)', m1.id, m1.team_a_player_ids, m1.team_b_player_ids), 'callouts are in progress');
  perform t.as_user(1);
  perform t.expect_error(format('select make_callout(%L, %L, %L)', s1, array[t.u(8)], m1.team_b_player_ids), 'not available');
  -- A takes the unit currently in match 2 and asks to face match 1's B pair
  perform make_callout(s1, m2.team_a_player_ids, m1.team_b_player_ids);
  select * into m1 from tournament_matchups where id = m1.id;
  select * into m2 from tournament_matchups where id = m2.id;
  perform t.assert(m1.team_a_player_ids = m2.team_a_player_ids is false and m1.called_by_team_id = ta and m1.called_at is not null, 'called match locked by A');
  perform t.assert(m1.team_a_player_ids = a1 or m1.team_a_player_ids = a2, 'caller unit moved into the called slot');
  -- one match left: nothing to choose, so the session locks
  perform t.assert((select status from tournament_sessions where id = s1) = 'locked', 'session locked after last decision');
  perform t.assert((select bool_and(status = 'active' and called_at is not null) from tournament_matchups where session_id = s1), 'all matches active and locked');
  perform t.assert((select count(distinct u) from tournament_matchups, unnest(team_a_player_ids) u where session_id = s1) = 4, 'no player lost or duplicated by the swap');

  -- finish both matches: A wins one, halves the other
  perform t.finish_match(m1.id, 70, 80);
  perform t.assert((select status from tournament_sessions where id = s1) = 'locked', 'session not complete until all matches are');
  perform t.finish_match(m2.id, 75, 75);
  perform t.assert((select status from tournament_sessions where id = s1) = 'complete', 'session completes');
  perform t.assert((select status from tournament_sessions where id = s2) = 'lineup', 'next session opens in lineup');
  perform t.assert((select bool_and(array_length(team_a_player_ids, 1) = 1 and array_length(team_b_player_ids, 1) = 1)
                      from tournament_matchups where session_id = s2), 'next session auto-filled with singles');

  -- A leads 1.5-0.5, so B (trailing) calls first in session 2
  perform t.as_user(1);
  perform open_callouts(s2);
  perform t.assert((select turn_team_id from tournament_sessions where id = s2) = tb, 'trailing team calls first');
  perform t.as_user(1);
  perform t.expect_error(format('select pass_callout(%L)', s2), 'not your turn');
  perform t.as_user(5);
  perform pass_callout(s2);
  perform t.assert((select turn_team_id from tournament_sessions where id = s2) = ta and (select consecutive_passes from tournament_sessions where id = s2) = 1, 'pass hands over the turn');
  perform t.as_user(1);
  perform pass_callout(s2);
  perform t.assert((select status from tournament_sessions where id = s2) = 'locked', 'two passes lock the session');
  perform t.assert((select count(*) from tournament_matchups where session_id = s2 and status = 'active') = 4, 'all four singles playable');
  -- admin override can still fix a locked match (size must fit the format)
  select * into mm from tournament_matchups where session_id = s2 order by matchup_number limit 1;
  perform t.expect_error(format('select set_pairings(%L, %L, %L)', mm.id, array[t.u(1), t.u(2)], array[t.u(5), t.u(6)]), 'pick 1 player');
end $$;

-- ---------------------------------------------------------------- sit-outs rotate; players are not repeated while others rest
do $$ declare v uuid; s1 uuid; s2 uuid; begin
  -- 5 v 4 singles twice: A has 5 players, only 4 play each session
  v := t.sessions_fixture(array[1,2,3,4,8], array[5,6,7,9], array['match_play','match_play']);
  perform t.as_user(1);
  perform start_tournament(v);
  select id into s1 from tournament_sessions where tournament_id = v and session_number = 1;
  select id into s2 from tournament_sessions where tournament_id = v and session_number = 2;
  perform t.assert(not exists (select 1 from tournament_matchups where session_id = s1 and t.u(8) = any (team_a_player_ids)), 'last draft pick sits session 1');
  perform open_callouts(s1);
  perform pass_callout(s1);
  perform t.as_user(5);
  perform pass_callout(s1);
  perform t.assert((select status from tournament_sessions where id = s1) = 'locked', 'session 1 locked');
  perform t.as_user(1);
  perform t.finish_match(id, 70, 80) from tournament_matchups where session_id = s1;
  perform t.assert((select status from tournament_sessions where id = s2) = 'lineup', 'session 2 opened');
  perform t.assert(exists (select 1 from tournament_matchups where session_id = s2 and t.u(8) = any (team_a_player_ids)), 'rested player plays session 2');
  perform t.assert(not exists (select 1 from tournament_matchups where session_id = s2 and t.u(4) = any (team_a_player_ids)), 'most-played, latest-drafted player now sits');
end $$;

-- ---------------------------------------------------------------- privileges
do $$ begin
  perform t.assert(not has_function_privilege('anon', 'make_callout(uuid, uuid[], uuid[], boolean)', 'execute'), 'anon cannot call make_callout');
  perform t.assert(has_function_privilege('authenticated', 'make_callout(uuid, uuid[], uuid[], boolean)', 'execute'), 'authenticated can call make_callout');
  perform t.assert(not has_function_privilege('authenticated', '_autofill_session(uuid)', 'execute'), 'internal helper is not callable');
end $$;

-- ---------------------------------------------------------------- planning writes (RLS)
select t.sessions_fixture(array[1,2], array[5,6], array['best_ball']) as draft_id \gset
set role authenticated;
select t.as_user(1);
do $$ declare v uuid; begin
  select id into v from tournaments where name = 'S' and status = 'draft' limit 1;
  insert into tournament_sessions (tournament_id, day_number, session_number, match_type) values (v, 2, 1, 'match_play');
  perform t.assert((select count(*) from tournament_sessions where tournament_id = v) = 2, 'creator can add a session while drafting');
  perform t.expect_error(format('insert into tournament_sessions (tournament_id, day_number, session_number, match_type, status) values (%L, 3, 1, ''match_play'', ''locked'')', v), 'row-level security');
  perform t.expect_error(format('update tournament_sessions set status = ''locked'' where tournament_id = %L', v), 'row-level security');
  -- a started tournament is closed to direct edits
  select id into v from tournaments where name = 'S' and status = 'active' limit 1;
  perform t.expect_error(format('insert into tournament_sessions (tournament_id, day_number, session_number, match_type) values (%L, 9, 1, ''match_play'')', v), 'row-level security');
end $$;
select t.as_user(2);
do $$ declare v uuid; begin
  select id into v from tournaments where name = 'S' and status = 'draft' limit 1;
  perform t.expect_error(format('insert into tournament_sessions (tournament_id, day_number, session_number, match_type) values (%L, 5, 1, ''match_play'')', v), 'row-level security');
end $$;
reset role;
