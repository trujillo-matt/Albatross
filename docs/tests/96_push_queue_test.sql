-- Tests for migration 023: the turn alert goes to the captain, tee time reminders go out once, claims are not repeated.
do $$ declare v uuid; s uuid; n int; begin
  v := t.sessions_fixture(array[1,2,3,4], array[5,6,7,8], array['match_play']);
  perform t.as_user(1);
  perform start_tournament(v);
  s := (select id from tournament_sessions where tournament_id = v);
  delete from push_queue;
  perform open_callouts(s);
  perform t.assert((select count(*) from push_queue where kind = 'your_turn') = 1, 'opening the callouts alerts one captain');
  perform t.assert((select user_id from push_queue where kind = 'your_turn') in (t.u(1), t.u(5)), 'and it is a captain');
  perform t.assert((select time_sensitive from push_queue where kind = 'your_turn'), 'the turn alert is time sensitive');
  perform t.assert((select body from push_queue where kind = 'your_turn') like '%turn to call a match%', 'in words that say what to do');

  -- tee times: two players an hour away, one far off, one with no time
  delete from push_queue;
  insert into tournament_tee_times (session_id, tournament_id, user_id, tee_time) values
    (s, v, t.u(2), now() + interval '57 minutes'), (s, v, t.u(3), now() + interval '57 minutes'), (s, v, t.u(4), now() + interval '5 hours');
  n := queue_tee_time_reminders();
  perform t.assert(n = 2, 'two players get a reminder, not the one five hours out');
  perform t.assert((select body from push_queue where user_id = t.u(2) and kind = 'tee_time') like '%with %', 'the reminder names the group');
  perform t.assert(queue_tee_time_reminders() = 0, 'a second run adds nothing');
  perform t.assert((select count(*) from push_queue where kind = 'tee_time') = 2, 'still two rows');

  -- claims
  perform t.assert((select count(*) from claim_push_queue(10)) = 2, 'a drain claims what is waiting');
  perform t.assert((select count(*) from claim_push_queue(10)) = 0, 'and the next drain finds nothing');
end $$;
