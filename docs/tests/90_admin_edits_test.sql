-- Tests for migrations 018 to 021: admin edits re-score the match, admin result overrides, roster changes after the draft.
-- Uses helpers from 10_rules_test.sql.

-- ---------------------------------------------------------------- 018: an edit re-scores the match
do $$ declare m record; r uuid; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.play(2, m.mid, t.flat(4)); perform t.play(3, m.mid, t.flat(6));
  perform t.play(4, m.mid, t.flat(5)); perform t.play(5, m.mid, t.flat(5));
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'A wins before the edit');
  -- the admin finds A's best card was really 6s all round: A is then 108 against B 90
  perform t.as_user(1);
  for h in 1..18 loop
    perform admin_set_hole_score((select r2.id from rounds r2 where r2.matchup_id = m.mid and r2.user_id = t.u(2)), h, 6, 'card was misread');
  end loop;
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_b_win', 'the result flips with the edit, no recompute needed');
  perform t.assert((select points_team_b from tournament_matchups where id = m.mid) = 1, 'B has the point');
  -- A's total climbs from 72 to 108 one hole at a time: it wins, then ties at 90 (after hole 9), then loses (hole 10). Two changes.
  perform t.assert((select count(*) from tournament_audit_log where target_id = m.mid and action = 'edit_changed_result') = 2, 'each change of result is audited');
  perform t.assert(exists (select 1 from tournament_audit_log where target_id = m.mid and action = 'edit_changed_result' and before ->> 'result' = 'team_a_win' and after ->> 'result' = 'tie'), 'win to tie is recorded');
  perform t.assert(exists (select 1 from tournament_audit_log where target_id = m.mid and action = 'edit_changed_result' and before ->> 'result' = 'tie' and after ->> 'result' = 'team_b_win'), 'tie to loss is recorded');
  perform t.assert((select count(*) from tournament_audit_log where target_id = m.mid and action = 'edit_changed_result' and reason = 'card was misread') = 2, 'with the reason given');
  perform t.assert((select count(*) from tournament_audit_log where action = 'edit_hole_score' and target_id in (select id from rounds where matchup_id = m.mid)) = 18, 'each hole edit is audited');
end $$;

-- an edit that does not change the outcome writes no result entry
do $$ declare m record; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.play(2, m.mid, t.flat(4)); perform t.play(3, m.mid, t.flat(6));
  perform t.play(4, m.mid, t.flat(5)); perform t.play(5, m.mid, t.flat(5));
  perform t.as_user(1);
  perform admin_set_hole_score((select id from rounds where matchup_id = m.mid and user_id = t.u(3)), 1, 7, 'typo on the worse card');
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'still A');
  perform t.assert((select count(*) from tournament_audit_log where target_id = m.mid and action = 'edit_changed_result') = 0, 'no result entry when nothing changed');
end $$;

-- editing a card while the match is still being played changes no result
do $$ declare m record; begin
  select * into m from t.matchup('match_play', '{2}', '{3}');
  perform t.play(2, m.mid, t.flat(4));
  perform t.as_user(1);
  perform admin_set_hole_score((select id from rounds where matchup_id = m.mid and user_id = t.u(2)), 1, 3, 'edit while the other card is out');
  perform t.assert((select status from tournament_matchups where id = m.mid) = 'active', 'still active');
end $$;

-- ---------------------------------------------------------------- 019: a result set by hand
do $$ declare m record; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.as_user(2);
  perform t.expect_error(format('select admin_set_result(%L, 1, 0, %L, %L)', m.mid, 'forfeit', 'no show'), 'admin only');
  perform t.as_user(1);
  perform t.expect_error(format('select admin_set_result(%L, 1, 0, %L, %L)', m.mid, 'forfeit', ''), 'reason required');
  perform t.expect_error(format('select admin_set_result(%L, 1, 0, %L, %L)', m.mid, 'tantrum', 'why'), 'kind must be');
  perform t.expect_error(format('select admin_set_result(%L, 2, 0, %L, %L)', m.mid, 'forfeit', 'why'), 'points must be');
  perform t.expect_error(format('select admin_set_result(%L, 1, 1, %L, %L)', m.mid, 'forfeit', 'why'), 'worth 1 point');
  perform t.anon();
  perform t.expect_error(format('select admin_set_result(%L, 1, 0, %L, %L)', m.mid, 'forfeit', 'why'), 'admin only|permission denied');
end $$;

-- a forfeit: B did not show, A gets the point, nothing has been scored
do $$ declare m record; begin
  select * into m from t.matchup('best_ball', '{2,3}', '{4,5}');
  perform t.as_user(1);
  perform admin_set_result(m.mid, 1, 0, 'forfeit', 'Team B did not arrive');
  perform t.assert((select status from tournament_matchups where id = m.mid) = 'complete', 'the match is complete');
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'result follows the points');
  perform t.assert((select points_team_a from tournament_matchups where id = m.mid) = 1, 'A has the point');
  perform t.assert((select count(*) from tournament_audit_log where target_id = m.mid and action = 'set_result' and reason = 'Team B did not arrive' and after ->> 'kind' = 'forfeit') = 1, 'audited with kind and reason');
  -- cards that turn up later, and an edit, do not overwrite it
  perform t.play(2, m.mid, t.flat(6)); perform t.play(3, m.mid, t.flat(6));
  perform t.play(4, m.mid, t.flat(3)); perform t.play(5, m.mid, t.flat(3));
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'scoring does not overwrite a hand-set result');
  perform admin_set_hole_score((select id from rounds where matchup_id = m.mid and user_id = t.u(4)), 1, 9, 'typo');
  perform t.assert((select points_team_a from tournament_matchups where id = m.mid) = 1, 'neither does a score edit');
  perform t.expect_error(format('select admin_recompute_matchup(%L)', m.mid), 'clear it first');
  -- clearing hands it back to the cards: B shot 3s, so B wins
  perform t.expect_error(format('select admin_clear_result(%L, %L)', m.mid, ''), 'reason required');
  perform admin_clear_result(m.mid, 'they arrived after all');
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_b_win', 'cleared: scored from the cards again');
  perform t.assert((select result_override from tournament_matchups where id = m.mid) = false, 'override is off');
  perform t.assert((select count(*) from tournament_audit_log where target_id = m.mid and action = 'clear_result') = 1, 'clearing is audited');
  perform t.expect_error(format('select admin_clear_result(%L, %L)', m.mid, 'again'), 'not set by an admin');
end $$;

-- a rainout can halve the match or give nobody a point, and the rest of the rules still run
do $$ declare v uuid; ta uuid; tb uuid; m1 uuid; m2 uuid; begin
  v := t.new_tournament(2, 'active');
  update tournaments set points_to_win = 1.5 where id = v;
  select id into ta from tournament_teams where tournament_id = v and side = 'A';
  select id into tb from tournament_teams where tournament_id = v and side = 'B';
  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, match_type, status)
    values (v, 1, ta, tb, array[t.u(2)], array[t.u(3)], 'stroke_play', 'active') returning id into m1;
  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, match_type, status)
    values (v, 2, ta, tb, array[t.u(2)], array[t.u(3)], 'stroke_play', 'active') returning id into m2;
  perform t.as_user(1);
  perform admin_set_result(m1, 0.5, 0.5, 'rainout', 'course closed');
  perform t.assert((select result from tournament_matchups where id = m1) = 'tie', 'halved is a tie');
  perform t.assert((select status from tournaments where id = v) = 'active', 'not finished at 0.5 points');
  perform admin_set_result(m2, 1, 0, 'forfeit', 'no show');
  perform t.assert((select status from tournaments where id = v) = 'complete', 'the tournament completes when a team reaches the points to win');
  perform admin_set_result(m1, 0, 0, 'rainout', 'abandoned, no points');
  perform t.assert((select points_team_a + points_team_b from tournament_matchups where id = m1) = 0, 'no points for either team');
end $$;

-- a hand-set result closes the session like a played one, and opens the next
do $$ declare v uuid; s1 uuid; s2 uuid; begin
  v := t.sessions_fixture(array[1,2,3,4], array[5,6,7,8], array['best_ball','match_play']);
  perform t.as_user(1);
  perform start_tournament(v);
  select id into s1 from tournament_sessions where tournament_id = v and session_number = 1;
  select id into s2 from tournament_sessions where tournament_id = v and session_number = 2;
  perform t.assert((select status from tournament_sessions where id = s2) = 'pending', 'second session waits');
  perform autofill_session(s1);
  perform admin_set_result(m.id, 1, 0, 'forfeit', 'no show') from tournament_matchups m where m.session_id = s1;
  perform t.assert((select status from tournament_sessions where id = s1) = 'complete', 'the session closes when its last match is set');
  perform t.assert((select status from tournament_sessions where id = s2) <> 'pending', 'and the next session opens');
end $$;

-- ---------------------------------------------------------------- 020: removing a player after the draft
do $$ declare v uuid; ta uuid; tb uuid; m1 uuid; begin
  v := t.new_tournament(2, 'active');
  select id into ta from tournament_teams where tournament_id = v and side = 'A';
  select id into tb from tournament_teams where tournament_id = v and side = 'B';
  -- players 2 and 3 on A, 4 and 5 on B; 6 is on A and sits out
  insert into tournament_players (tournament_id, user_id, team_id, invite_status) select v, t.u(n), case when n in (2,3,6) then ta else tb end, 'accepted' from generate_series(2, 6) n on conflict do nothing;
  update tournament_players set team_id = case when user_id in (t.u(2), t.u(3), t.u(6)) then ta else tb end, invite_status = 'accepted' where tournament_id = v and user_id <> t.u(1);
  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, match_type, status)
    values (v, 1, ta, tb, array[t.u(2), t.u(3)], array[t.u(4), t.u(5)], 'best_ball', 'active') returning id into m1;
  perform t.as_user(2);
  perform t.expect_error(format('select admin_remove_player(%L, %L, %L)', v, t.u(6), 'dropped out'), 'admin only');
  perform t.as_user(1);
  perform t.expect_error(format('select admin_remove_player(%L, %L, %L)', v, t.u(6), ''), 'reason required');
  perform t.expect_error(format('select admin_remove_player(%L, %L, %L)', v, t.u(1), 'x'), 'organizer cannot be removed');
  update tournament_teams set captain_user_id = t.u(3) where id = ta;
  perform t.expect_error(format('select admin_remove_player(%L, %L, %L)', v, t.u(3), 'x'), 'a captain cannot be removed');
  update tournament_teams set captain_user_id = null where id = ta;
  perform t.expect_error(format('select admin_remove_player(%L, %L, %L)', v, t.u(2), 'x'), 'in match 1 which has not finished');
  perform t.expect_error(format('select admin_remove_player(%L, %L, %L)', v, t.u(99), 'x'), 'not on the roster');
  -- the sit-out can go
  perform admin_remove_player(v, t.u(6), 'flew home');
  perform t.assert((select invite_status from tournament_players where tournament_id = v and user_id = t.u(6)) = 'declined', 'removed: no longer accepted');
  perform t.assert((select team_id from tournament_players where tournament_id = v and user_id = t.u(6)) is null, 'and off the team');
  perform t.assert((select count(*) from tournament_audit_log where tournament_id = v and action = 'remove_player' and reason = 'flew home') = 1, 'audited with the reason');
  perform t.expect_error(format('select admin_remove_player(%L, %L, %L)', v, t.u(6), 'again'), 'not on the roster');
  -- a player in a finished match can be removed afterwards and keeps their place in its history
  update tournament_matchups set status = 'complete', result = 'team_a_win', points_team_a = 1 where id = m1;
  perform admin_remove_player(v, t.u(5), 'injured after the match');
  perform t.assert((select team_b_player_ids from tournament_matchups where id = m1) @> array[t.u(5)], 'the finished match keeps its players');
end $$;

-- ---------------------------------------------------------------- 021: a tiebreak match for a points split
do $$ declare v uuid; ta uuid; tb uuid; m1 uuid; m2 uuid; tie uuid; begin
  v := t.new_tournament(2, 'active');
  select id into ta from tournament_teams where tournament_id = v and side = 'A';
  select id into tb from tournament_teams where tournament_id = v and side = 'B';
  update tournament_players set team_id = case when user_id in (t.u(2), t.u(3)) then ta else tb end, invite_status = 'accepted' where tournament_id = v and user_id <> t.u(1);
  insert into tournament_players (tournament_id, user_id, team_id, invite_status) values (v, t.u(2), ta, 'accepted'), (v, t.u(3), ta, 'accepted'), (v, t.u(4), tb, 'accepted'), (v, t.u(5), tb, 'accepted') on conflict do nothing;
  update tournament_players set team_id = case when user_id in (t.u(2), t.u(3)) then ta else tb end, invite_status = 'accepted' where tournament_id = v and user_id <> t.u(1);
  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, match_type, status)
    values (v, 1, ta, tb, array[t.u(2)], array[t.u(4)], 'match_play', 'active') returning id into m1;
  insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, team_a_player_ids, team_b_player_ids, match_type, status)
    values (v, 2, ta, tb, array[t.u(3)], array[t.u(5)], 'match_play', 'active') returning id into m2;
  update tournaments set total_matches = 2 where id = v;
  perform t.as_user(1);
  perform t.expect_error(format('select admin_add_tiebreak(%L, %L, %L, %L)', v, t.u(2), t.u(4), 'level'), 'finish the 2 unfinished');
  -- A wins match 1, B wins match 2: one point each
  perform t.play(2, m1, t.flat(3)); perform t.play(4, m1, t.flat(4));
  perform t.play(3, m2, t.flat(4)); perform t.play(5, m2, t.flat(3));
  perform t.assert((select points_team_a from tournament_matchups where id = m1) = 1 and (select points_team_b from tournament_matchups where id = m2) = 1, 'one point each');
  perform t.assert((select status from tournaments where id = v) = 'complete', 'a split finishes the tournament as it stands');
  perform t.as_user(2);
  perform t.expect_error(format('select admin_add_tiebreak(%L, %L, %L, %L)', v, t.u(2), t.u(4), 'level'), 'admin only');
  perform t.as_user(1);
  perform t.expect_error(format('select admin_add_tiebreak(%L, %L, %L, %L)', v, t.u(2), t.u(4), ''), 'reason required');
  perform t.expect_error(format('select admin_add_tiebreak(%L, %L, %L, %L)', v, t.u(4), t.u(2), 'level'), 'player A must be on the first team');
  perform t.expect_error(format('select admin_add_tiebreak(%L, %L, %L, %L)', v, t.u(2), t.u(3), 'level'), 'player B must be on the second team');
  tie := admin_add_tiebreak(v, t.u(2), t.u(4), 'points split 1 to 1');
  perform t.assert((select status from tournaments where id = v) = 'active', 'the tournament is open again');
  perform t.assert((select total_matches from tournaments where id = v) = 3, 'the count includes the tiebreak');
  perform t.assert((select matchup_number from tournament_matchups where id = tie) = 3 and (select session_id from tournament_matchups where id = tie) is null, 'a plain match with no session');
  perform t.assert((select count(*) from tournament_audit_log where target_id = tie and action = 'add_tiebreak' and reason = 'points split 1 to 1') = 1, 'audited');
  perform t.expect_error(format('select admin_add_tiebreak(%L, %L, %L, %L)', v, t.u(2), t.u(4), 'again'), 'finish the 1 unfinished');
  -- B wins it: the tournament finishes with B ahead
  perform t.play(2, tie, t.flat(5)); perform t.play(4, tie, t.flat(4));
  perform t.assert((select result from tournament_matchups where id = tie) = 'team_b_win', 'the tiebreak is scored like any match');
  perform t.assert((select status from tournaments where id = v) = 'complete', 'and the tournament is complete again');
  perform t.expect_error(format('select admin_add_tiebreak(%L, %L, %L, %L)', v, t.u(2), t.u(4), 'again'), 'not level');
end $$;
