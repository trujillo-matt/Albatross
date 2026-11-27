-- 023: alerts that are not news: "your turn to call a match" and "tee time in an hour".
-- Anything that should reach a phone is a row in push_queue. A statement trigger asks the drain-push-queue edge function
-- to send what is waiting; the function claims each row before sending, so a row is sent once. Tee time reminders are
-- queued every five minutes by pg_cron. Nothing here can block a callout or a score: failures are swallowed.
begin;

do $$ begin
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_net not available (%): queued alerts wait for the next drain', sqlerrm;
end $$;
do $$ begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron not available (%): tee time reminders are not scheduled', sqlerrm;
end $$;

create table if not exists push_queue (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  kind           text not null check (kind in ('your_turn', 'tee_time')),
  title          text not null,
  body           text not null,
  data           jsonb not null default '{}'::jsonb,
  time_sensitive boolean not null default false,
  dedupe_key     text unique,
  created_at     timestamptz not null default now(),
  sent_at        timestamptz
);
create index if not exists push_queue_waiting on push_queue (created_at) where sent_at is null;
alter table push_queue enable row level security;
revoke all on push_queue from anon, authenticated;

-- The drain function takes the next batch. skip locked keeps two drains from taking the same row.
create or replace function claim_push_queue(p_limit int default 50) returns setof push_queue
language sql security definer set search_path = public as $$
  update push_queue set sent_at = now()
   where id in (select id from push_queue where sent_at is null order by created_at limit greatest(1, least(coalesce(p_limit, 50), 200)) for update skip locked)
  returning *
$$;
revoke all on function claim_push_queue(int) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function claim_push_queue(int) to service_role;
  end if;
end $$;

-- After rows are queued, ask the edge function to send them.
create or replace function push_queue_kick() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    perform net.http_post(
      url     := 'https://rtcyetcyhdrajvcstvlj.supabase.co/functions/v1/drain-push-queue',
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body    := '{}'::jsonb);
  exception when others then
    null;
  end;
  return null;
end $$;
revoke all on function push_queue_kick() from public, anon, authenticated;
drop trigger if exists push_queue_kick on push_queue;
create trigger push_queue_kick after insert on push_queue
  for each statement execute function push_queue_kick();

-- Callouts alternate between the two captains. When the turn moves to a team, its captain is told.
create or replace function push_on_callout_turn() returns trigger language plpgsql security definer set search_path = public as $$
declare cap uuid; team_name text; tname text;
begin
  if new.turn_team_id is null or new.turn_team_id is not distinct from old.turn_team_id then return new; end if;
  select captain_user_id, name into cap, team_name from tournament_teams where id = new.turn_team_id;
  if cap is null then return new; end if;
  select name into tname from tournaments where id = new.tournament_id;
  insert into push_queue (user_id, kind, title, body, data, time_sensitive)
  values (cap, 'your_turn', 'Your turn to call a match',
          'It is ' || coalesce(team_name, 'your team') || '''s turn to call a match in the ' || coalesce(tname, 'tournament')
            || ', day ' || new.day_number || '. The other captain is waiting on you.',
          jsonb_build_object('tournament_id', new.tournament_id, 'session_id', new.id), true);
  return new;
end $$;
revoke all on function push_on_callout_turn() from public, anon, authenticated;
drop trigger if exists push_callout_turn on tournament_sessions;
create trigger push_callout_turn after update of turn_team_id on tournament_sessions
  for each row execute function push_on_callout_turn();

-- Players with a tee time 50 to 65 minutes away get a reminder, once. The window is wider than the five minute schedule
-- so a missed run does not skip anyone; the dedupe key keeps it to one alert.
create or replace function queue_tee_time_reminders() returns int language plpgsql security definer set search_path = public as $$
declare added int;
begin
  insert into push_queue (user_id, kind, title, body, data, time_sensitive, dedupe_key)
  select tt.user_id, 'tee_time', 'Tee time in about an hour',
         'You tee off in about an hour' || coalesce(' at ' || nullif(s.course_name, ''), '')
           || coalesce(' with ' || (select string_agg(p.display_name, ', ' order by p.display_name)
                                      from tournament_tee_times o join profiles p on p.id = o.user_id
                                     where o.session_id = tt.session_id and o.tee_time = tt.tee_time and o.user_id <> tt.user_id), '')
           || '.',
         jsonb_build_object('tournament_id', tt.tournament_id, 'session_id', tt.session_id), true,
         'tee:' || tt.session_id || ':' || tt.user_id
    from tournament_tee_times tt
    join tournament_sessions s on s.id = tt.session_id
    join tournament_players tp on tp.tournament_id = tt.tournament_id and tp.user_id = tt.user_id and tp.invite_status = 'accepted'
   where tt.tee_time between now() + interval '50 minutes' and now() + interval '65 minutes'
  on conflict (dedupe_key) do nothing;
  get diagnostics added = row_count;
  return added;
end $$;
revoke all on function queue_tee_time_reminders() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'tee-time-reminders';
    perform cron.schedule('tee-time-reminders', '*/5 * * * *', 'select queue_tee_time_reminders()');
  end if;
exception when others then
  raise notice 'could not schedule tee time reminders: %', sqlerrm;
end $$;

commit;
