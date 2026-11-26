-- Tests for migration 017: the shamble format. Uses helpers from 10_rules_test.sql.

-- the format is accepted where formats are stored, and junk still is not
do $$ declare v uuid := t.new_tournament(1, 'draft'); begin
  update tournaments set match_type = 'shamble' where id = v;
  perform t.assert((select match_type from tournaments where id = v) = 'shamble', 'a tournament can use shamble');
  perform t.expect_error(format('update tournaments set match_type = %L where id = %L', 'bogus', v), 'violates check constraint');
  insert into tournament_sessions (tournament_id, day_number, session_number, label, match_type)
    values (v, 1, 1, 'Shamble', 'shamble');
  perform t.assert((select count(*) from tournament_sessions where tournament_id = v and match_type = 'shamble') = 1, 'a session can use shamble');
  perform t.expect_error(format('insert into tournament_sessions (tournament_id, day_number, session_number, match_type) values (%L, 1, 2, %L)', v, 'bogus'), 'violates check constraint');
end $$;

-- two players a side, like every pairs format; singles stay at one
do $$ begin
  perform t.assert(players_per_side('shamble') = 2, 'shamble has two players a side');
  perform t.assert(players_per_side('scramble') = 2 and players_per_side('best_ball') = 2 and players_per_side('alternate_shot') = 2, 'other pairs formats unchanged');
  perform t.assert(players_per_side('match_play') = 1 and players_per_side('stroke_play') = 1, 'singles unchanged');
end $$;

-- scoring is best ball: A has a 4 card and a 6 card (best 4s), B two 5 cards -> A wins, and it waits for all four cards
do $$ declare m record; begin
  select * into m from t.matchup('shamble', '{2,3}', '{4,5}');
  perform t.play(2, m.mid, t.flat(4)); perform t.play(3, m.mid, t.flat(6));
  perform t.play(4, m.mid, t.flat(5));
  perform t.assert((select status from tournament_matchups where id = m.mid) = 'active', 'shamble waits for every player card, not one per side');
  perform t.play(5, m.mid, t.flat(5));
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'shamble: lower team total wins');
  perform t.assert((select points_team_a from tournament_matchups where id = m.mid) = 1 and (select points_team_b from tournament_matchups where id = m.mid) = 0, 'winner gets 1 point');
end $$;

-- the lower score per hole counts, not each side's lowest single total (this is where it differs from stroke play):
-- A: one player 4s on the front, 6s on the back; the other 6s then 4s. Best ball = 4 every hole = 72.
-- B: both players 5s = 90. Stroke play would give A 90 (min of 90, 90) against B 90 and halve it.
do $$ declare m record; mixed_a jsonb; mixed_b jsonb; begin
  select * into m from t.matchup('shamble', '{2,3}', '{4,5}');
  mixed_a := (select to_jsonb(array(select case when i <= 9 then 4 else 6 end from generate_series(1, 18) i)));
  mixed_b := (select to_jsonb(array(select case when i <= 9 then 6 else 4 end from generate_series(1, 18) i)));
  perform t.play(2, m.mid, mixed_a); perform t.play(3, m.mid, mixed_b);
  perform t.play(4, m.mid, t.flat(5)); perform t.play(5, m.mid, t.flat(5));
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'team_a_win', 'shamble takes the lower score on each hole');
end $$;

-- equal best ball totals are a tie, 0.5 each
do $$ declare m record; begin
  select * into m from t.matchup('shamble', '{2,3}', '{4,5}');
  perform t.play(2, m.mid, t.flat(4)); perform t.play(3, m.mid, t.flat(6));
  perform t.play(4, m.mid, t.flat(4)); perform t.play(5, m.mid, t.flat(7));
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'tie', 'equal totals tie');
  perform t.assert((select points_team_a from tournament_matchups where id = m.mid) = 0.5 and (select points_team_b from tournament_matchups where id = m.mid) = 0.5, '0.5 each');
end $$;

-- group scoring: one card per player, not one per side
do $$ declare m record; n int; begin
  select * into m from t.matchup('shamble', '{2,3}', '{4,5}');
  perform t.as_user(2); perform set_scorer(m.mid, t.u(2));
  select count(*) into n from start_group_scoring(m.mid);
  perform t.assert(n = 4 and t.cards(m.mid) = 4, 'shamble gets one card per player');
  perform t.fill(m.mid, 4);
  perform finish_group_scoring(m.mid);
  perform t.assert((select result from tournament_matchups where id = m.mid) = 'tie', 'all-4s group card ties');
end $$;
