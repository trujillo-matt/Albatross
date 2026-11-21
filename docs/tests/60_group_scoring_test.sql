-- Tests for migration 009: one person keeps score for the whole group. Uses helpers from 10_rules_test.sql.
create function t.cards(mid uuid) returns int language sql as $$ select count(*)::int from rounds where matchup_id = mid $$;
create function t.fill(mid uuid, strokes int) returns void language plpgsql as $$
declare r record; h int;
begin
  for r in select id from rounds where matchup_id = mid loop
    for h in 1..18 loop perform set_hole_score(r.id, h, strokes); end loop;
  end loop;
end $$;

-- ---------------------------------------------------------------- volunteering and assigning
do $$ declare m record; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');   -- A: users 2,3   B: users 4,5   admin: user 1
  perform t.as_user(8);   -- not in the match
  perform t.expect_error(format('select set_scorer(%L, %L)', m.mid, t.u(8)), 'only players in this match');
  perform t.as_user(2);
  perform t.expect_error(format('select set_scorer(%L, %L)', m.mid, t.u(3)), 'only volunteer yourself');
  perform set_scorer(m.mid, t.u(2));
  perform t.assert((select scorer_user_id from tournament_matchups where id = m.mid) = t.u(2), 'a player can volunteer');
  perform t.as_user(4);
  perform t.expect_error(format('select set_scorer(%L, %L)', m.mid, t.u(4)), 'already keeping score');
  perform t.expect_error(format('select set_scorer(%L, null)', m.mid), 'only the current scorer can step down');
  perform t.as_user(2); perform set_scorer(m.mid, null);
  perform t.assert((select scorer_user_id from tournament_matchups where id = m.mid) is null, 'the scorer can step down');
  perform t.as_user(1);   -- organizer
  perform set_scorer(m.mid, t.u(4));
  perform t.assert((select scorer_user_id from tournament_matchups where id = m.mid) = t.u(4), 'an organizer can assign the scorer');
  perform set_scorer(m.mid, t.u(5));
  perform t.assert((select scorer_user_id from tournament_matchups where id = m.mid) = t.u(5), 'an organizer can reassign at any time');
  perform t.expect_error(format('select set_scorer(%L, %L)', m.mid, t.u(8)), 'must be playing in this match');
  perform t.assert((select count(*) from tournament_audit_log where target_id = m.mid and action = 'set_scorer') >= 3, 'assignments are audited');
  perform t.anon();
  perform t.expect_error(format('select set_scorer(%L, %L)', m.mid, t.u(2)), 'not signed in');
end $$;

do $$ declare v uuid := t.new_tournament(1, 'active'); ta uuid; tb uuid; mid uuid; begin
  select id into ta from tournament_teams where tournament_id = v and side = 'A';
  select id into tb from tournament_teams where tournament_id = v and side = 'B';
  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, match_type, status)
    values (v, 1, ta, tb, 'best_ball', 'pending') returning id into mid;
  perform t.as_user(1);
  perform t.expect_error(format('select set_scorer(%L, null)', mid), 'pairings are not set');
end $$;

-- ---------------------------------------------------------------- creating the group's cards
do $$ declare m record; n int; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.as_user(2); perform set_scorer(m.mid, t.u(2));
  perform t.as_user(3);
  perform t.expect_error(format('select * from start_group_scoring(%L)', m.mid), 'only the scorer');
  perform t.as_user(2);
  select count(*) into n from start_group_scoring(m.mid, '{"course_name":"Pebble","course_id":"pb","pars":[4,5,4,4,3,5,3,4,4,4,4,3,5,4,4,3,4,5],"rating":75.5,"slope":145}'::jsonb);
  perform t.assert(n = 4, 'one card per player in best ball');
  perform t.assert(t.cards(m.mid) = 4, '4 rounds exist');
  perform t.assert((select count(*) from tournament_matchup_rounds where matchup_id = m.mid) = 4, '4 links exist');
  perform t.assert((select count(*) from rounds where matchup_id = m.mid and course_name = 'Pebble' and course_rating = 75.5 and slope_rating = 145 and jsonb_array_length(course_pars) = 18) = 4, 'course details copied to every card');
  perform t.assert((select count(*) from rounds where matchup_id = m.mid and user_id <> t.u(2)) = 3, 'cards belong to each player');
  select count(*) into n from start_group_scoring(m.mid);   -- again
  perform t.assert(n = 4 and t.cards(m.mid) = 4, 'starting twice does not duplicate cards');
  perform t.as_user(1);
  select count(*) into n from start_group_scoring(m.mid);
  perform t.assert(n = 4, 'an organizer can start it too');
end $$;

do $$ declare m record; n int; begin
  select * into m from t.matchup('scramble', '{2,3}', '{4,5}');
  perform t.as_user(3); perform set_scorer(m.mid, t.u(3));
  select count(*) into n from start_group_scoring(m.mid);
  perform t.assert(n = 2 and t.cards(m.mid) = 2, 'team formats get one card per side');
  perform t.assert((select count(*) from rounds where matchup_id = m.mid and user_id in (t.u(2), t.u(4))) = 2, 'owned by the first player listed on each side');
end $$;

-- a card a player already started is kept, not duplicated
do $$ declare m record; n int; own uuid; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  own := t.card(3, m.mid, t.flat(4));
  insert into tournament_matchup_rounds (matchup_id, round_id, user_id) values (m.mid, own, t.u(3));
  perform t.as_user(2); perform set_scorer(m.mid, t.u(2));
  select count(*) into n from start_group_scoring(m.mid);
  perform t.assert(n = 4 and t.cards(m.mid) = 4, 'an existing card is reused');
  perform t.assert((select count(*) from rounds where id = own) = 1, 'the existing card is untouched');
end $$;

-- ---------------------------------------------------------------- writing strokes
do $$ declare m record; rb uuid; other record; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.as_user(2); perform set_scorer(m.mid, t.u(2)); perform start_group_scoring(m.mid);
  select id into rb from rounds where matchup_id = m.mid and user_id = t.u(4);
  perform set_hole_score(rb, 1, 5);
  perform t.assert((select scores -> 0 from rounds where id = rb) = '5', 'the scorer wrote another player''s hole');
  perform t.as_user(4);   -- the card's owner, but someone else is scoring
  perform t.expect_error(format('select set_hole_score(%L, 2, 4)', rb), 'not yours|round not found');
  perform t.as_user(8);
  perform t.expect_error(format('select set_hole_score(%L, 2, 4)', rb), 'round not found');
  -- the scorer cannot reach into a different match
  select * into other from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.as_user(1); perform start_group_scoring(other.mid);
  perform t.as_user(2);
  perform t.expect_error(format('select set_hole_score(%L, 1, 4)', (select id from rounds where matchup_id = other.mid and user_id = t.u(4))), 'round not found');
  -- stepping down hands cards back to their owners
  perform set_scorer(m.mid, null);
  perform t.as_user(4); perform set_hole_score(rb, 2, 4);
  perform t.assert((select scores -> 1 from rounds where id = rb) = '4', 'with no scorer the owner writes their own card again');
end $$;

-- ---------------------------------------------------------------- the lock against direct writes
do $$ declare m record; rb uuid; rs uuid; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.as_user(2); perform set_scorer(m.mid, t.u(2)); perform start_group_scoring(m.mid);
  select id into rb from rounds where matchup_id = m.mid and user_id = t.u(4);
  select id into rs from rounds where matchup_id = m.mid and user_id = t.u(2);
end $$;
do $$ declare m record; rb uuid; rs uuid; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.as_user(2); perform set_scorer(m.mid, t.u(2)); perform start_group_scoring(m.mid);
  select id into rb from rounds where matchup_id = m.mid and user_id = t.u(4);
  select id into rs from rounds where matchup_id = m.mid and user_id = t.u(2);
  perform set_config('t.rb', rb::text, false); perform set_config('t.rs', rs::text, false); perform set_config('t.mid', m.mid::text, false);
end $$;
set role authenticated;
select t.as_user(4);
do $$ begin
  perform t.expect_error(format($q$update rounds set scores = jsonb_set(scores, '{0}', '3') where id = %L$q$, current_setting('t.rb')), 'scorer is keeping score');
  perform t.expect_error(format($q$update rounds set status = 'completed' where id = %L$q$, current_setting('t.rb')), 'scorer is keeping score');
  perform t.expect_error(format($q$insert into rounds (id, user_id, course_name, date, scores, matchup_id) values (gen_random_uuid(), %L, 'C', now(), '[]', %L)$q$, t.u(4), current_setting('t.mid')), 'scorer is keeping score');
  -- unrelated updates to the card (nothing in scores or status) still work
  update rounds set course_name = 'Renamed' where id = current_setting('t.rb')::uuid;
end $$;
select t.as_user(2);
do $$ begin
  update rounds set scores = jsonb_set(scores, '{0}', '3') where id = current_setting('t.rs')::uuid;   -- the scorer's own card, directly
  perform t.assert((select scores -> 0 from rounds where id = current_setting('t.rs')::uuid) = '3', 'the scorer can still write their own card directly');
end $$;
reset role;

-- ---------------------------------------------------------------- finishing together and the result
do $$ declare m record; n int; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.as_user(2); perform set_scorer(m.mid, t.u(2)); perform start_group_scoring(m.mid);
  perform t.expect_error(format('select finish_group_scoring(%L)', m.mid), 'all 18 holes');
  -- Team A shoots 4s, Team B shoots 5s
  perform set_hole_score(r.id, h, case when r.user_id in (t.u(2), t.u(3)) then 4 else 5 end)
     from rounds r, generate_series(1, 18) h where r.matchup_id = m.mid;
  perform t.assert((select count(*) from rounds where matchup_id = m.mid and status = 'in_progress') = 4, 'cards stay open until submitted');
  perform t.as_user(3);
  perform t.expect_error(format('select finish_group_scoring(%L)', m.mid), 'only the scorer');
  perform t.as_user(2); perform finish_group_scoring(m.mid);
  perform t.assert((select count(*) from rounds where matchup_id = m.mid and status = 'completed') = 4, 'every card is submitted together');
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'the database computed the result');
  perform t.assert((select points_team_a from tournament_matchups where id = m.mid) = 1, 'Team A got the point');
  perform t.expect_error(format('select set_hole_score(%L, 1, 3)', (select id from rounds where matchup_id = m.mid limit 1)), 'round not found');
  perform t.expect_error(format('select set_scorer(%L, null)', m.mid), 'already complete');
end $$;

do $$ declare m record; begin   -- scramble: two cards, finished by the scorer
  select * into m from t.matchup('scramble', '{2,3}', '{4,5}');
  perform t.as_user(1); perform set_scorer(m.mid, t.u(3));
  perform t.as_user(3); perform start_group_scoring(m.mid);
  perform set_hole_score(r.id, h, case when r.user_id = t.u(2) then 3 else 4 end) from rounds r, generate_series(1, 18) h where r.matchup_id = m.mid;
  perform finish_group_scoring(m.mid);
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'scramble resolves from the two team cards');
end $$;

-- ---------------------------------------------------------------- privileges
set role anon;
do $$ begin
  perform t.expect_error($q$select set_scorer(gen_random_uuid(), null)$q$, 'permission denied');
  perform t.expect_error($q$select * from start_group_scoring(gen_random_uuid())$q$, 'permission denied');
  perform t.expect_error($q$select finish_group_scoring(gen_random_uuid())$q$, 'permission denied');
  perform t.expect_error($q$select matchup_scorer(gen_random_uuid())$q$, 'permission denied');
end $$;
reset role;
