-- Tests for migration 024: who may follow a match, the standing, and the one-update-per-match queue.
do $$ declare m record; ra uuid; rb uuid; r record; begin
  select * into m from t.matchup('match_play', '{2}', '{3}');
  ra := t.card(2, m.mid, t.nulls());
  rb := t.card(3, m.mid, t.nulls());

  perform t.as_user(2);
  perform register_live_activity_token(m.mid, 'tok-1');
  perform t.assert((select user_id from live_activity_tokens where token = 'tok-1') = t.u(2), 'a player follows their match');
  perform t.as_user(9);   -- outsider
  perform t.expect_error(format('select register_live_activity_token(%L, %L)', m.mid, 'tok-2'), 'not in this tournament');
  perform t.assert(not exists (select 1 from live_activity_tokens where token = 'tok-2'), 'an outsider cannot');
  perform t.as_user(3);
  perform unregister_live_activity_token('tok-1');
  perform t.assert(exists (select 1 from live_activity_tokens where token = 'tok-1'), 'nobody removes another account''s token');

  -- A is a stroke better on three holes: 3 up through 3 in match play
  delete from live_activity_queue;
  perform t.as_user(2); update rounds set scores = t.holes(4, 4, 4, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null) where id = ra;
  perform t.as_user(3); update rounds set scores = t.holes(5, 5, 5, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null) where id = rb;
  select * into r from match_live_status(m.mid);
  perform t.assert(r.lead = 3 and r.thru = 3 and not r.finished, 'match play: 3 up through 3');
  perform t.assert((select count(*) from live_activity_queue) = 2, 'each score change queues the match');
  perform t.assert((select count(*) from claim_live_activity_matchups(10)) = 1, 'a drain sees the match once');
  perform t.assert((select count(*) from claim_live_activity_matchups(10)) = 0, 'and then nothing is left');
end $$;

-- other formats count strokes: A 4s against B 5s over three holes is 3 strokes ahead
do $$ declare m record; ra uuid; rb uuid; r record; begin
  select * into m from t.matchup('best_ball', '{2}', '{3}');
  ra := t.card(2, m.mid, t.holes(4, 4, 4, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null));
  rb := t.card(3, m.mid, t.holes(5, 6, 5, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null));
  select * into r from match_live_status(m.mid);
  perform t.assert(r.lead = 4 and r.thru = 3, 'best ball: 4 strokes ahead through 3');
  -- a match nobody follows queues nothing
  delete from live_activity_queue;
  perform t.as_user(2); update rounds set scores = t.flat(4) where id = ra;
  perform t.assert((select count(*) from live_activity_queue) = 0, 'no followers, no queue');
end $$;
