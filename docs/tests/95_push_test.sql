-- Tests for migration 022: device tokens belong to their owner, and a news row is stored whether or not the push can be sent.
do $$ begin
  perform t.as_user(2);
  perform register_device_token('tok-a');
  perform t.assert((select user_id from device_tokens where token = 'tok-a') = t.u(2), 'a token is saved for the caller');
  perform t.as_user(3);
  perform register_device_token('tok-a', false);
  perform t.assert((select user_id from device_tokens where token = 'tok-a') = t.u(3), 'a token seen under another account moves to it');
  perform t.assert((select enabled from device_tokens where token = 'tok-a') = false, 'and takes the new setting');
  perform t.as_user(2);
  perform unregister_device_token('tok-a');
  perform t.assert(exists (select 1 from device_tokens where token = 'tok-a'), 'nobody can remove another account''s token');
  perform t.as_user(3);
  perform unregister_device_token('tok-a');
  perform t.assert(not exists (select 1 from device_tokens where token = 'tok-a'), 'the owner can remove it');
end $$;

do $$ declare m record; begin
  select * into m from t.matchup('match_play', '{2}', '{3}');
  -- the push trigger runs on this insert; without pg_net or the function it must not get in the way
  insert into tournament_news (tournament_id, matchup_id, kind, headline)
    values ((select tournament_id from tournament_matchups where id = m.mid), m.mid, 'lead_change', 'test');
  perform t.assert(exists (select 1 from tournament_news where headline = 'test' and pushed_at is null), 'news is stored even when the push cannot be sent');
end $$;
