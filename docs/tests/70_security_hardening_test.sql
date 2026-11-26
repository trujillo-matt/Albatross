-- Tests for migration 014. Uses helpers from 10_rules_test.sql.
-- A match whose session is not locked cannot be scored; once locked it can.
do $$ declare m record; s uuid; r uuid; begin
  select * into m from t.matchup('match_play', '{2}', '{4}');
  insert into tournament_sessions (tournament_id, day_number, session_number, match_type, status)
    values (m.tid, 1, 1, 'match_play', 'callouts') returning id into s;
  update tournament_matchups set session_id = s where id = m.mid;
  r := t.card(2, m.mid, t.flat(0)::jsonb, 'in_progress');
  perform t.as_user(2);
  perform t.expect_error(format('select set_hole_score(%L, 1, 4)', r), 'not open for scoring');
  update tournament_sessions set status = 'locked' where id = s;
  perform set_hole_score(r, 1, 4);
  perform t.assert(true, 'scoring works once the session is locked');
end $$;

-- the profile view is read-only and closed to signed-out users
do $$ begin
  perform t.assert(not has_table_privilege('anon', 'profile_with_counts', 'select'), 'anon cannot read the profile view');
  perform t.assert(has_table_privilege('authenticated', 'profile_with_counts', 'select'), 'signed-in users can read it');
  perform t.assert(not has_table_privilege('authenticated', 'profile_with_counts', 'update'), 'nobody can write through it');
  perform t.assert(not has_table_privilege('authenticated', 'player_access_codes', 'select'), 'codes are not readable by clients');
  perform t.assert(not has_table_privilege('authenticated', 'tournament_audit_log', 'select'), 'audit log is not readable by clients');
  perform t.assert(not has_function_privilege('anon', 'handle_new_user()', 'execute'), 'signup trigger is not callable');
end $$;

-- clients no longer touch the code, attempt and audit tables at all (reads fail instead of returning no rows)
set role authenticated;
do $$ begin
  perform t.expect_error('select count(*) from player_access_codes', 'permission denied');
  perform t.expect_error('select count(*) from tournament_audit_log', 'permission denied');
  perform t.expect_error('select count(*) from code_redeem_attempts', 'permission denied');
end $$;
reset role;

-- 015: public standings carry sessions and each match's session
do $$ declare v uuid; tok text; j jsonb; begin
  v := t.new_tournament(3, 'active');
  tok := repeat('a', 40);
  update tournaments set public_token = tok where id = v;
  insert into tournament_sessions (tournament_id, day_number, session_number, match_type, status) values (v, 1, 1, 'match_play', 'locked');
  j := get_public_standings(tok);
  perform t.assert(jsonb_array_length(j -> 'sessions') = 1, 'standings list the sessions');
  perform t.assert(j ? 'teams' and j ? 'matchups', 'existing keys are unchanged');
end $$;

-- 016: lead changes in match play
do $$ declare m record; ra uuid; rb uuid; n int; begin
  select * into m from t.matchup('match_play', '{2}', '{4}');
  ra := t.card(2, m.mid, to_jsonb(array_fill(null::int, array[18])), 'in_progress');
  rb := t.card(4, m.mid, to_jsonb(array_fill(null::int, array[18])), 'in_progress');
  update rounds set scores = (select jsonb_agg(case when i <= 8 then 3 else null end) from generate_series(1, 18) i) where id = ra;
  perform t.assert((select count(*) from tournament_news where matchup_id = m.mid and kind = 'lead_change') = 0, 'no lead with one card');
  update rounds set scores = (select jsonb_agg(case when i <= 3 then 4 else null end) from generate_series(1, 18) i) where id = rb;
  perform t.assert((select count(*) from tournament_news where matchup_id = m.mid and kind = 'lead_change' and headline like '%took the lead in match 1, 3 up through 3') = 1, 'A takes the lead');
  update rounds set scores = (select jsonb_agg(case when i <= 3 then 4 when i <= 6 then 2 else null end) from generate_series(1, 18) i) where id = rb;
  perform t.assert((select count(*) from tournament_news where matchup_id = m.mid and kind = 'lead_change' and headline like '%all square through 6') = 1, 'back to all square');
  update rounds set scores = (select jsonb_agg(case when i <= 3 then 4 when i <= 7 then 2 else null end) from generate_series(1, 18) i) where id = rb;
  perform t.assert((select count(*) from tournament_news where matchup_id = m.mid and kind = 'lead_change') = 3, 'B takes the lead');
  update rounds set scores = (select jsonb_agg(case when i <= 3 then 4 when i <= 8 then 2 else null end) from generate_series(1, 18) i) where id = rb;
  perform t.assert((select count(*) from tournament_news where matchup_id = m.mid and kind = 'lead_change') = 3, 'extending a lead is not news');
end $$;
