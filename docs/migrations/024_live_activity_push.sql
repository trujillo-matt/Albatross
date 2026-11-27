-- 024: Live Activity updates over push.
-- A phone showing a match on the lock screen registers the activity's push token for that match. When a score on the
-- match changes, the match goes in live_activity_queue; the drain-push-queue edge function reads the standing once
-- with match_live_status and sends it to every registered token. Nothing here can block a score: failures are swallowed.
begin;

create table if not exists live_activity_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  matchup_id uuid not null references tournament_matchups(id) on delete cascade,
  updated_at timestamptz not null default now()
);
create index if not exists live_activity_tokens_matchup on live_activity_tokens (matchup_id);
alter table live_activity_tokens enable row level security;
revoke all on live_activity_tokens from anon, authenticated;

create table if not exists live_activity_queue (
  id         uuid primary key default gen_random_uuid(),
  matchup_id uuid not null references tournament_matchups(id) on delete cascade,
  created_at timestamptz not null default now(),
  sent_at    timestamptz
);
create index if not exists live_activity_queue_waiting on live_activity_queue (created_at) where sent_at is null;
alter table live_activity_queue enable row level security;
revoke all on live_activity_queue from anon, authenticated;

-- Only people in the tournament can follow one of its matches.
create or replace function register_live_activity_token(p_matchup uuid, p_token text)
returns void language plpgsql security definer set search_path = public as $$
declare tid uuid;
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  if coalesce(trim(p_token), '') = '' then raise exception 'token required'; end if;
  select tournament_id into tid from tournament_matchups where id = p_matchup;
  if tid is null or not is_tournament_member(tid) then raise exception 'not in this tournament'; end if;
  insert into live_activity_tokens (token, user_id, matchup_id) values (p_token, auth.uid(), p_matchup)
  on conflict (token) do update set user_id = auth.uid(), matchup_id = p_matchup, updated_at = now();
end $$;

create or replace function unregister_live_activity_token(p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  delete from live_activity_tokens where token = p_token and user_id = auth.uid();
end $$;

revoke all on function register_live_activity_token(uuid, text), unregister_live_activity_token(text) from public, anon;
grant execute on function register_live_activity_token(uuid, text), unregister_live_activity_token(text) to authenticated;

-- Where a match stands, from side A's view: holes up in match play, strokes ahead in the other formats, over the holes
-- both sides have scored. The same rule as match_play_status and the apps (each side's best score on a hole).
create or replace function match_live_status(p_matchup uuid)
returns table (lead int, thru int, finished boolean) language sql stable security definer set search_path = public as $$
  with m as (select team_a_player_ids a_ids, team_b_player_ids b_ids, match_type, status from tournament_matchups where id = p_matchup),
  cards as (
    select case when r.user_id = any (m.a_ids) then 'A' when r.user_id = any (m.b_ids) then 'B' end side, r.scores sc
      from rounds r, m where r.matchup_id = p_matchup
  ),
  holes as (
    select (select min((c.sc ->> h)::int) from cards c where c.side = 'A') a,
           (select min((c.sc ->> h)::int) from cards c where c.side = 'B') b
      from generate_series(0, 17) h
  )
  select coalesce(sum(case when (select match_type from m) = 'match_play' then sign(b - a) else b - a end), 0)::int,
         count(*)::int,
         coalesce((select status = 'complete' from m), false)
    from holes where a is not null and b is not null
$$;
revoke all on function match_live_status(uuid) from public, anon, authenticated;

-- A score changed on a followed match.
create or replace function live_activity_on_score() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.matchup_id is null or new.scores is not distinct from old.scores then return new; end if;
  if exists (select 1 from live_activity_tokens where matchup_id = new.matchup_id) then
    insert into live_activity_queue (matchup_id) values (new.matchup_id);
  end if;
  return new;
end $$;
revoke all on function live_activity_on_score() from public, anon, authenticated;
drop trigger if exists live_activity_score on rounds;
create trigger live_activity_score after update of scores on rounds
  for each row execute function live_activity_on_score();

-- The matches with waiting updates, once each however many scores changed. Old tokens are dropped on the way:
-- a Live Activity lasts hours, not days.
create or replace function claim_live_activity_matchups(p_limit int default 50) returns table (matchup_id uuid)
language plpgsql security definer set search_path = public as $$
begin
  delete from live_activity_tokens where updated_at < now() - interval '1 day';
  return query
    with taken as (
      update live_activity_queue set sent_at = now()
       where id in (select q.id from live_activity_queue q where q.sent_at is null order by q.created_at
                     limit greatest(1, least(coalesce(p_limit, 50), 500)) for update skip locked)
      returning live_activity_queue.matchup_id
    )
    select distinct taken.matchup_id from taken;
end $$;
revoke all on function claim_live_activity_matchups(int) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function claim_live_activity_matchups(int), match_live_status(uuid) to service_role;
  end if;
end $$;

-- Same drain as the alerts.
create or replace function live_activity_queue_kick() returns trigger language plpgsql security definer set search_path = public as $$
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
revoke all on function live_activity_queue_kick() from public, anon, authenticated;
drop trigger if exists live_activity_queue_kick on live_activity_queue;
create trigger live_activity_queue_kick after insert on live_activity_queue
  for each statement execute function live_activity_queue_kick();

commit;
