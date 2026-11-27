-- 022: push notifications for tournament news.
-- A phone registers its APNs token; when a news row is added, a trigger asks the send-news-push edge function to alert
-- every accepted player of that tournament. The function marks the row as pushed first, so a repeat call changes nothing.
-- The push can never block the news: a failure to reach the function is swallowed and the row is stored either way.
begin;

do $$ begin
  create extension if not exists pg_net with schema extensions;
exception when others then
  raise notice 'pg_net not available (%): news will be stored but not pushed', sqlerrm;
end $$;

create table if not exists device_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  enabled    boolean not null default true,
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user on device_tokens (user_id);
alter table device_tokens enable row level security;
revoke all on device_tokens from anon, authenticated;

-- A phone saves its own token. A token seen again under another account moves to that account.
create or replace function register_device_token(p_token text, p_enabled boolean default true)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  if coalesce(trim(p_token), '') = '' then raise exception 'token required'; end if;
  insert into device_tokens (token, user_id, enabled) values (p_token, auth.uid(), coalesce(p_enabled, true))
  on conflict (token) do update set user_id = auth.uid(), enabled = coalesce(p_enabled, true), updated_at = now();
end $$;

create or replace function unregister_device_token(p_token text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in first'; end if;
  delete from device_tokens where token = p_token and user_id = auth.uid();
end $$;

revoke all on function register_device_token(text, boolean), unregister_device_token(text) from public, anon;
grant execute on function register_device_token(text, boolean), unregister_device_token(text) to authenticated;

alter table tournament_news add column if not exists pushed_at timestamptz;

create or replace function news_push_after_insert() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    perform net.http_post(
      url     := 'https://rtcyetcyhdrajvcstvlj.supabase.co/functions/v1/send-news-push',
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body    := jsonb_build_object('id', new.id));
  exception when others then
    null;
  end;
  return new;
end $$;
revoke all on function news_push_after_insert() from public, anon, authenticated;

drop trigger if exists news_push on tournament_news;
create trigger news_push after insert on tournament_news
  for each row execute function news_push_after_insert();

commit;
