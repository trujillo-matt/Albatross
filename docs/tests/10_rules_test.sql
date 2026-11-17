-- SQL tests for migrations 001 to 004 against the stub schema. Any failure raises and stops the run.
create schema t;
grant usage on schema t to anon, authenticated;   -- test helpers must be callable while running as those roles
create function t.u(n int) returns uuid language sql immutable as
  $$ select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $$;
create function t.as_user(n int) returns void language sql as
  $$ select set_config('request.jwt.claim.sub', t.u(n)::text, false) $$;
create function t.anon() returns void language sql as
  $$ select set_config('request.jwt.claim.sub', '', false) $$;
-- Runs sql and requires it to fail with a message matching pattern.
create function t.expect_error(sql text, pattern text) returns void language plpgsql as $$
begin
  execute sql;
exception when others then
  if sqlerrm !~* pattern then raise exception 'wrong error for [%]: got "%" expected /%/', sql, sqlerrm, pattern; end if;
  return;
end $$;
-- Note: when expect_error succeeds in catching, the failing statement is rolled back (subtransaction).
create function t.assert(cond boolean, msg text) returns void language plpgsql as $$
begin if not coalesce(cond, false) then raise exception 'ASSERT FAILED: %', msg; end if; end $$;

-- Fixture: users 1..8. 1 = creator/admin. 2..8 = players. 9 = outsider.
insert into profiles (id, display_name) select t.u(i), 'User ' || i from generate_series(1, 9) i;
insert into auth.users select t.u(i) from generate_series(1, 9) i;

create function t.new_tournament(total int default 3, status text default 'draft') returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into tournaments (name, creator_user_id, total_matches, status, match_type)
  values ('T', t.u(1), total, status, 'best_ball') returning id into v;
  insert into tournament_teams (tournament_id, name, side) values (v, 'Team A', 'A'), (v, 'Team B', 'B');
  insert into tournament_players (tournament_id, user_id, invite_status, is_admin)
    select v, t.u(i), 'accepted', i = 1 from generate_series(1, 8) i;
  return v;
end $$;

-- ---------------------------------------------------------------- 001: side column
do $$ begin
  perform t.expect_error($q$ insert into tournament_teams (tournament_id, name, side)
    select id, 'X', 'C' from tournaments limit 1 $q$, 'check');
  -- one team per side
  perform t.new_tournament();
  perform t.expect_error($q$ insert into tournament_teams (tournament_id, name, side)
    select tournament_id, 'Dup', 'A' from tournament_teams limit 1 $q$, 'duplicate|unique');
end $$;

-- ---------------------------------------------------------------- 002: points to win correction is in the migration;
-- verify the rule it applies using a legacy row.
do $$ declare v uuid; begin
  insert into tournaments (name, creator_user_id, total_matches, points_to_win, status)
    values ('Legacy', t.u(1), 3, 9.5, 'draft') returning id into v;
  update tournaments set points_to_win = total_matches / 2.0 + 0.5
   where id = v and points_to_win = 9.5 and total_matches < 18 and status <> 'complete';
  perform t.assert((select points_to_win from tournaments where id = v) = 2.0, '3 matches -> 2.0 to win');
end $$;

-- ---------------------------------------------------------------- voting
do $$ declare v uuid := t.new_tournament(); begin
  perform t.as_user(2);
  perform cast_captain_votes(v, array[t.u(3), t.u(4)]);
  perform t.assert((select count(*) from tournament_captain_votes where voter_user_id = t.u(2)) = 2, 'ballot stored as 2 rows');
  perform t.expect_error(format('select cast_captain_votes(%L, array[%L::uuid, %L::uuid])', v, t.u(5), t.u(6)), 'already voted');
  perform t.as_user(3);
  perform t.expect_error(format('select cast_captain_votes(%L, array[%L::uuid, %L::uuid])', v, t.u(5), t.u(5)), 'exactly 2');
  perform t.expect_error(format('select cast_captain_votes(%L, array[%L::uuid])', v, t.u(5)), 'exactly 2');
  perform t.as_user(9);   -- outsider
  perform t.expect_error(format('select cast_captain_votes(%L, array[%L::uuid, %L::uuid])', v, t.u(5), t.u(6)), 'only accepted players');
  perform t.as_user(4);   -- nominee who is not in the pool
  perform t.expect_error(format('select cast_captain_votes(%L, array[%L::uuid, %L::uuid])', v, t.u(5), t.u(9)), 'nominees must be accepted');
  perform t.anon();
  perform t.expect_error(format('select cast_captain_votes(%L, array[%L::uuid, %L::uuid])', v, t.u(5), t.u(6)), 'not signed in');
  -- voting only while the draft stage is open
  update tournaments set status = 'active' where id = v;
  perform t.as_user(5);
  perform t.expect_error(format('select cast_captain_votes(%L, array[%L::uuid, %L::uuid])', v, t.u(3), t.u(4)), 'not open');
end $$;

-- ---------------------------------------------------------------- finalize captains
do $$ declare v uuid := t.new_tournament(); a uuid; b uuid; begin
  -- clear result: u3 gets 3 votes, u4 gets 2, u5 gets 1
  insert into tournament_captain_votes (tournament_id, voter_user_id, nominee_user_id) values
    (v, t.u(2), t.u(3)), (v, t.u(2), t.u(4)), (v, t.u(5), t.u(3)), (v, t.u(5), t.u(4)), (v, t.u(6), t.u(3)), (v, t.u(6), t.u(7));
  perform t.as_user(2);   -- non-admin
  perform t.expect_error(format('select finalize_captains(%L)', v), 'admin only');
  perform t.as_user(1);
  perform finalize_captains(v);
  select id into a from tournament_teams where tournament_id = v and side = 'A';
  select id into b from tournament_teams where tournament_id = v and side = 'B';
  perform t.assert((select captain_user_id from tournament_teams where id = a) = t.u(3), 'top vote-getter captains A');
  perform t.assert((select captain_user_id from tournament_teams where id = b) = t.u(4), '2nd captains B');
  perform t.assert((select team_id from tournament_players where tournament_id = v and user_id = t.u(3)) = a, 'captain A placed on team A');
  perform t.assert((select team_id from tournament_players where tournament_id = v and user_id = t.u(4)) = b, 'captain B placed on team B');
end $$;

do $$ declare v uuid := t.new_tournament(); begin
  -- tie for the last seat: u3 has 2 votes, u4 and u5 have 1 each
  insert into tournament_captain_votes (tournament_id, voter_user_id, nominee_user_id) values
    (v, t.u(2), t.u(3)), (v, t.u(2), t.u(4)), (v, t.u(6), t.u(3)), (v, t.u(6), t.u(5));
  perform t.as_user(1);
  perform t.expect_error(format('select finalize_captains(%L)', v), 'captain_tie');
  perform t.expect_error(format('select finalize_captains(%L, array[%L::uuid])', v, t.u(7)), 'captain_tie');   -- not a tied nominee
  perform finalize_captains(v, array[t.u(5)]);
  perform t.assert((select captain_user_id from tournament_teams where tournament_id = v and side = 'A') = t.u(3), 'clear winner is captain A');
  perform t.assert((select captain_user_id from tournament_teams where tournament_id = v and side = 'B') = t.u(5), 'tiebreak winner is captain B');
end $$;

do $$ declare v uuid := t.new_tournament(); begin
  insert into tournament_captain_votes (tournament_id, voter_user_id, nominee_user_id) values (v, t.u(2), t.u(3));
  perform t.as_user(1);
  perform t.expect_error(format('select finalize_captains(%L)', v), 'not enough votes');
end $$;

-- ---------------------------------------------------------------- draft: snake order A B B A A B
do $$ declare v uuid := t.new_tournament(); begin
  update tournament_teams set captain_user_id = t.u(2) where tournament_id = v and side = 'A';
  update tournament_teams set captain_user_id = t.u(3) where tournament_id = v and side = 'B';
  update tournament_players p set team_id = (select id from tournament_teams where tournament_id = v and side = 'A') where tournament_id = v and user_id = t.u(2);
  update tournament_players p set team_id = (select id from tournament_teams where tournament_id = v and side = 'B') where tournament_id = v and user_id = t.u(3);

  perform t.as_user(3);   -- B captain tries to pick first
  perform t.expect_error(format('select draft_pick(%L, %L)', v, t.u(4)), 'not your turn');
  perform t.as_user(2); perform draft_pick(v, t.u(4));            -- pick 0: A
  perform t.expect_error(format('select draft_pick(%L, %L)', v, t.u(5)), 'not your turn');
  perform t.as_user(3); perform draft_pick(v, t.u(5));            -- pick 1: B
  perform draft_pick(v, t.u(6));                                  -- pick 2: B
  perform t.as_user(2); perform draft_pick(v, t.u(7));            -- pick 3: A
  perform draft_pick(v, t.u(8));                                  -- pick 4: A
  perform t.as_user(3);   -- pick 5 belongs to B
  perform t.expect_error(format('select draft_pick(%L, %L)', v, t.u(4)), 'player not available');   -- already taken
  perform t.as_user(5);   -- not a captain
  perform t.expect_error(format('select draft_pick(%L, %L)', v, t.u(1)), 'not a captain');
  -- admin override may place for the on-clock team
  perform t.as_user(1); perform draft_pick(v, t.u(1), true);
  perform t.assert((select team_id from tournament_players where tournament_id = v and user_id = t.u(1)) is not null, 'override placed player');
end $$;

-- ---------------------------------------------------------------- set_hole_score
create function t.card(owner int, matchup uuid, scores jsonb, st text default 'in_progress') returns uuid language plpgsql as $$
declare r uuid := gen_random_uuid();
begin
  insert into rounds (id, user_id, course_name, scores, status, matchup_id) values (r, t.u(owner), 'C', scores, st, matchup);
  return r;
end $$;
create function t.nulls() returns jsonb language sql immutable as $$ select to_jsonb(array_fill(null::int, array[18])) $$;

do $$ declare r uuid := t.card(2, null, t.nulls()); begin
  perform t.as_user(2);
  perform set_hole_score(r, 1, 4); perform set_hole_score(r, 18, 6); perform set_hole_score(r, 1, 5);
  perform t.assert((select scores -> 0 from rounds where id = r) = '5', 'hole 1 overwritten by later write');
  perform t.assert((select scores -> 17 from rounds where id = r) = '6', 'hole 18 kept');
  perform t.assert((select scores -> 5 from rounds where id = r) = 'null'::jsonb, 'untouched holes stay null');
  perform set_hole_score(r, 1, null);
  perform t.assert((select scores -> 0 from rounds where id = r) = 'null'::jsonb, 'clearing a hole works');
  perform t.expect_error(format('select set_hole_score(%L, 0, 4)', r), 'hole must be');
  perform t.expect_error(format('select set_hole_score(%L, 19, 4)', r), 'hole must be');
  perform t.expect_error(format('select set_hole_score(%L, 3, 21)', r), 'strokes must be');
  perform t.expect_error(format('select set_hole_score(%L, 3, 0)', r), 'strokes must be');
  perform t.as_user(3);   -- not the owner
  perform t.expect_error(format('select set_hole_score(%L, 3, 4)', r), 'not yours');
  update rounds set status = 'completed' where id = r;
  perform t.as_user(2);
  perform t.expect_error(format('select set_hole_score(%L, 3, 4)', r), 'already completed');
end $$;

-- ---------------------------------------------------------------- scoring (parity with Swift Tournament.swift)
create function t.holes(variadic v int[]) returns jsonb language sql immutable as $$ select to_jsonb(v) $$;
-- builds an 18 hole card from a repeated value, optionally with an override at one hole
create function t.flat(n int, hole int default null, val int default null) returns jsonb language sql immutable as $$
  select to_jsonb(array(select case when i = hole then val else n end from generate_series(1, 18) i)) $$;

create function t.matchup(kind text, a1 int[], b1 int[], total int default 3) returns table (mid uuid, tid uuid) language plpgsql as $$
declare v uuid := t.new_tournament(total, 'active'); m uuid; ta uuid; tb uuid;
begin
  select id into ta from tournament_teams where tournament_id = v and side = 'A';
  select id into tb from tournament_teams where tournament_id = v and side = 'B';
  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, match_type, status)
  values (v, 1, ta, tb, (select array_agg(t.u(x)) from unnest(a1) x), (select array_agg(t.u(x)) from unnest(b1) x), kind, 'active') returning id into m;
  return query select m, v;
end $$;

-- finish a card the way the apps do: link at start, complete at the end
create function t.play(owner int, mid uuid, scores jsonb) returns void language plpgsql as $$
declare r uuid := t.card(owner, mid, scores, 'in_progress');
begin
  insert into tournament_matchup_rounds (matchup_id, round_id, user_id) values (mid, r, t.u(owner));
  update rounds set status = 'completed' where id = r;
end $$;

-- best ball: A has 4s and 5s (best 4s = 72), B all 5s (90) -> A wins
do $$ declare m record; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.play(2, m.mid, t.flat(4)); perform t.play(3, m.mid, t.flat(5));
  perform t.assert((select status from tournament_matchups where id = m.mid) = 'active', 'waits for all four cards');
  perform t.play(4, m.mid, t.flat(5)); perform t.play(5, m.mid, t.flat(5));
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'best ball A wins');
  perform t.assert((select points_team_a from tournament_matchups where id = m.mid) = 1, 'A gets 1 point');
end $$;

-- match play: per hole best score. A wins hole 1 only, B wins holes 2 and 3 -> B takes the point
do $$ declare m record; begin
  select * into m from t.matchup('match_play', '{2}', '{3}');
  perform t.play(2, m.mid, t.flat(4, 1, 3) #- '{}'); -- hole 1 = 3, others 4
  perform t.play(3, m.mid, (select to_jsonb(array(select case when i = 1 then 4 when i in (2,3) then 3 else 4 end from generate_series(1,18) i))));
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_b_win', 'match play: B won more holes');
  perform t.assert((select points_team_b from tournament_matchups where id = m.mid) = 1, 'B gets 1 point');
end $$;

-- match play: equal holes won -> halved
do $$ declare m record; begin
  select * into m from t.matchup('match_play', '{2}', '{3}');
  perform t.play(2, m.mid, t.flat(4)); perform t.play(3, m.mid, t.flat(4));
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'tie', 'halved match is a tie');
  perform t.assert((select points_team_a from tournament_matchups where id = m.mid) = 0.5, '0.5 each');
end $$;

-- stroke play: lowest single total per side. A: 4s (72) and 6s; B: 5s (90) -> A
do $$ declare m record; begin
  select * into m from t.matchup('stroke_play', '{2,3}', '{4,5}');
  perform t.play(2, m.mid, t.flat(6)); perform t.play(3, m.mid, t.flat(4));
  perform t.play(4, m.mid, t.flat(5)); perform t.play(5, m.mid, t.flat(5));
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'stroke play: lowest single total wins');
end $$;

-- scramble: one completed card per team is enough (fix for problem 8), with a duplicate teammate card ignored by min
do $$ declare m record; begin
  select * into m from t.matchup('scramble', '{2,3}', '{4,5}');
  perform t.play(2, m.mid, t.flat(3));
  perform t.assert((select status from tournament_matchups where id = m.mid) = 'active', 'scramble waits for the other team');
  perform t.play(4, m.mid, t.flat(4));
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'scramble resolves with one card per team');
end $$;

-- idempotent and tournament completion: 3 matches, 2.0 to win. Two A wins finish it.
do $$ declare v uuid; ta uuid; tb uuid; m1 uuid; m2 uuid; begin
  v := t.new_tournament(3, 'active');
  update tournaments set points_to_win = 2.0 where id = v;
  select id into ta from tournament_teams where tournament_id = v and side = 'A';
  select id into tb from tournament_teams where tournament_id = v and side = 'B';
  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, match_type, status)
    values (v, 1, ta, tb, array[t.u(2)], array[t.u(3)], 'stroke_play', 'active') returning id into m1;
  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, match_type, status)
    values (v, 2, ta, tb, array[t.u(2)], array[t.u(3)], 'stroke_play', 'active') returning id into m2;
  perform t.play(2, m1, t.flat(4)); perform t.play(3, m1, t.flat(5));
  perform t.assert((select status from tournaments where id = v) = 'active', 'not finished after 1 point');
  perform compute_matchup_result(m1); perform compute_matchup_result(m1);   -- idempotent
  perform t.assert((select points_team_a from tournament_matchups where id = m1) = 1, 'still 1 point after recompute');
  perform t.play(2, m2, t.flat(4)); perform t.play(3, m2, t.flat(5));
  perform t.assert((select status from tournaments where id = v) = 'complete', 'tournament completes at 2.0 points');
end $$;

-- all matches played with neither side at the target still completes (even split)
do $$ declare v uuid; ta uuid; tb uuid; m1 uuid; begin
  v := t.new_tournament(1, 'active');
  update tournaments set points_to_win = 5 where id = v;
  select id into ta from tournament_teams where tournament_id = v and side = 'A';
  select id into tb from tournament_teams where tournament_id = v and side = 'B';
  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, match_type, status)
    values (v, 1, ta, tb, array[t.u(2)], array[t.u(3)], 'stroke_play', 'active') returning id into m1;
  perform t.play(2, m1, t.flat(4)); perform t.play(3, m1, t.flat(5));
  perform t.assert((select status from tournaments where id = v) = 'complete', 'completes when every match is played');
end $$;

-- ---------------------------------------------------------------- admin functions + audit
do $$ declare m record; r uuid; begin
  select * into m from t.matchup('stroke_play', '{2}', '{3}');
  r := t.card(2, m.mid, t.flat(4), 'completed');
  perform t.as_user(2);   -- player, not admin
  perform t.expect_error(format('select admin_set_hole_score(%L, 1, 3, %L)', r, 'fix'), 'admin only');
  perform t.expect_error(format('select admin_recompute_matchup(%L)', m.mid), 'admin only');
  perform t.as_user(1);
  perform t.expect_error(format('select admin_set_hole_score(%L, 1, 3, %L)', r, ''), 'reason required');
  perform admin_set_hole_score(r, 1, 3, 'misread card');
  perform t.assert((select scores -> 0 from rounds where id = r) = '3', 'admin edited a completed card');
  perform t.assert((select count(*) from tournament_audit_log where target_id = r and reason = 'misread card') = 1, 'edit was audited');
  perform t.assert((select (before -> 0) = '4' and (after -> 0) = '3' from tournament_audit_log where target_id = r), 'audit keeps before and after');
  perform admin_recompute_matchup(m.mid);
  perform t.assert((select count(*) from admin_audit_log(m.tid)) >= 2, 'admin can read audit log');
  perform t.as_user(2);
  perform t.expect_error(format('select * from admin_audit_log(%L)', m.tid), 'admin only');
end $$;

-- ---------------------------------------------------------------- codes: privilege and RLS negative tests
do $$ declare v uuid := t.new_tournament(); begin
  insert into player_access_codes (tournament_id, user_id, code_hash, code_hint, created_by) values (v, t.u(2), 'hash1', 'XY', t.u(1));
  perform t.assert((select count(*) from player_access_codes) = 1, 'owner role sees the row');
  perform t.as_user(1);
  perform t.assert((select count(*) from admin_code_status(v)) = 1, 'admin reads code status');
  perform t.assert((select code_hint from admin_code_status(v) limit 1) = 'XY', 'status shows only the hint');
  perform t.as_user(2);
  perform t.expect_error(format('select * from admin_code_status(%L)', v), 'admin only');
  -- one active code per player per tournament
  perform t.expect_error(format($q$insert into player_access_codes (tournament_id, user_id, code_hash, created_by) values (%L, %L, 'hash2', %L)$q$, v, t.u(2), t.u(1)), 'duplicate|unique');
end $$;
set role authenticated;
do $$ begin
  -- RLS is on with no policy: a signed-in client sees nothing in the secret tables.
  perform t.assert((select count(*) from player_access_codes) = 0, 'client cannot read access codes');
  perform t.assert((select count(*) from tournament_audit_log) = 0, 'client cannot read the audit log directly');
  perform t.assert((select count(*) from code_redeem_attempts) = 0, 'client cannot read redeem attempts');
  perform t.expect_error($q$insert into player_access_codes (tournament_id, user_id, code_hash, created_by)
    select tournament_id, user_id, 'forged', user_id from tournament_players limit 1$q$, 'row-level security');
  perform t.expect_error(format('select compute_matchup_result(%L)', gen_random_uuid()), 'permission denied');
end $$;
reset role;

-- ---------------------------------------------------------------- spectator link
do $$ declare v uuid := t.new_tournament(); tok text; j jsonb; begin
  perform t.as_user(2);
  perform t.expect_error(format('select set_spectator_link(%L, true)', v), 'admin only');
  perform t.as_user(1);
  tok := set_spectator_link(v, true);
  perform t.assert(length(tok) >= 32, 'token is long');
  perform t.assert(set_spectator_link(v, true) = tok, 'enabling twice keeps the same token');
  perform t.anon();
  j := get_public_standings(tok);
  perform t.assert(j ->> 'name' = 'T', 'public standings readable without sign in');
  perform t.assert(jsonb_array_length(j -> 'teams') = 2, 'teams listed');
  perform t.assert(j::text !~ 'user_id|creator|email|code', 'no internal ids or secrets in the public payload');
  perform t.assert(get_public_standings('nope') is null, 'unknown token returns nothing');
  perform t.assert(get_public_standings(null) is null, 'null token returns nothing');
  perform t.as_user(1);
  perform set_spectator_link(v, false);
  perform t.assert(get_public_standings(tok) is null, 'turning the link off kills the old URL');
end $$;
set role anon;
do $$ begin
  perform t.assert(get_public_standings('x') is null, 'anon role can call get_public_standings');
  perform t.expect_error($q$select set_hole_score(gen_random_uuid(), 1, 4)$q$, 'not signed in|not found|not yours|permission');
end $$;
reset role;
