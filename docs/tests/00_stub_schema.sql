-- LOCAL COPY of the live Albatross schema (public tables, constraints, RLS policies, helper function and
-- signup trigger), captured read-only from the Supabase project on 2026-11-17, plus minimal stand-ins for
-- Supabase's own pieces (roles, auth.users, auth.uid). The policies are reproduced VERBATIM, including the
-- bugs the audit found. Only the data is absent.
create role anon nologin; create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key, raw_user_meta_data jsonb default '{}'::jsonb);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema public, auth to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;

create table profiles (id uuid primary key references auth.users(id) on delete cascade, display_name text not null default '',
  avatar_url text, created_at timestamptz default now(), updated_at timestamptz default now(), username text unique, home_course text, location text);
create table follows (follower_id uuid references auth.users(id) on delete cascade, following_id uuid references auth.users(id) on delete cascade,
  primary key (follower_id, following_id));
create table tournaments (
  id uuid primary key default gen_random_uuid(), name text not null, creator_user_id uuid not null references auth.users(id),
  status text not null default 'setup' check (status in ('setup','draft','active','complete')),
  match_type text not null check (match_type in ('scramble','best_ball','match_play','stroke_play')),
  total_matches int not null default 1, points_to_win numeric not null default 9.5,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table tournament_courses (id uuid primary key default gen_random_uuid(), tournament_id uuid not null references tournaments(id) on delete cascade,
  course_name text not null, round_number int not null default 1, match_type text);
create table tournament_teams (id uuid primary key default gen_random_uuid(), tournament_id uuid not null references tournaments(id) on delete cascade,
  name text not null, captain_user_id uuid references auth.users(id));
create table tournament_players (id uuid primary key default gen_random_uuid(), tournament_id uuid not null references tournaments(id) on delete cascade,
  user_id uuid not null references auth.users(id), team_id uuid references tournament_teams(id),
  invite_status text not null default 'pending' check (invite_status in ('pending','accepted','declined')),
  is_admin boolean not null default false, draft_position int, created_at timestamptz not null default now(),
  unique (tournament_id, user_id));
create table tournament_captain_votes (id uuid primary key default gen_random_uuid(), tournament_id uuid not null references tournaments(id) on delete cascade,
  voter_user_id uuid not null references auth.users(id), nominee_user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(), unique (tournament_id, voter_user_id, nominee_user_id));
create table tournament_matchups (id uuid primary key default gen_random_uuid(), tournament_id uuid not null references tournaments(id) on delete cascade,
  matchup_number int not null, team_a_id uuid not null references tournament_teams(id), team_b_id uuid not null references tournament_teams(id),
  team_a_player_ids uuid[] not null default '{}', team_b_player_ids uuid[] not null default '{}', match_type text not null,
  status text not null default 'pending' check (status in ('pending','active','complete')),
  result text check (result in ('team_a_win','team_b_win','tie')),
  points_team_a numeric default 0, points_team_b numeric default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table rounds (id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade, course_name text not null, course_id text,
  course_pars jsonb, course_handicaps jsonb, course_yardages jsonb, course_logo_filename text, date timestamptz not null, scores jsonb not null,
  status text not null default 'in_progress', updated_at timestamptz default now(), matchup_id uuid);
create table tournament_matchup_rounds (id uuid primary key default gen_random_uuid(),
  matchup_id uuid not null references tournament_matchups(id) on delete cascade, round_id uuid not null references rounds(id) on delete cascade,
  user_id uuid not null references auth.users(id), unique (matchup_id, user_id));

create view profile_with_counts as
  select id, display_name, avatar_url, created_at, updated_at, username, home_course, location,
         (select count(*) from follows where following_id = p.id)::int as followers_count,
         (select count(*) from follows where follower_id = p.id)::int as following_count from profiles p;

create function handle_new_user() returns trigger language plpgsql security definer as $$
begin
  insert into profiles (id, display_name, username)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), new.raw_user_meta_data->>'username')
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

create function is_tournament_member(tid uuid) returns boolean language sql stable security definer as $$
  select exists (select 1 from public.tournament_players where tournament_id = tid and user_id = auth.uid() and invite_status = 'accepted') $$;

-- RLS: verbatim from the live project.
do $$ declare r record; begin
  for r in select unnest(array['follows','profiles','rounds','tournament_captain_votes','tournament_courses','tournament_matchup_rounds',
                               'tournament_matchups','tournament_players','tournament_teams','tournaments']) t
  loop execute format('alter table %I enable row level security', r.t); end loop; end $$;

create policy "users manage own follows" on follows for all using (auth.uid() = follower_id);
create policy "anyone can read follows" on follows for select using (true);
create policy "users can manage own profile" on profiles for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "users can manage own rounds" on rounds for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "completed rounds are public" on rounds for select using (status = 'completed');
create policy "player can insert own vote" on tournament_captain_votes for insert with check (voter_user_id = auth.uid());
create policy "members can read votes" on tournament_captain_votes for select using (
  exists (select 1 from tournament_players tp where tp.tournament_id = tp.tournament_id and tp.user_id = auth.uid()));
create policy "creator can modify courses" on tournament_courses for all using (
  exists (select 1 from tournaments t where t.id = tournament_courses.tournament_id and t.creator_user_id = auth.uid()));
create policy "members can read courses" on tournament_courses for select using (
  exists (select 1 from tournaments t where t.id = tournament_courses.tournament_id and (t.creator_user_id = auth.uid() or
    exists (select 1 from tournament_players tp where tp.tournament_id = t.id and tp.user_id = auth.uid()))));
create policy "player can insert own matchup round" on tournament_matchup_rounds for insert with check (user_id = auth.uid());
create policy "members can read matchup rounds" on tournament_matchup_rounds for select using (
  exists (select 1 from tournament_matchups tm join tournament_players tp on tp.tournament_id = tm.tournament_id
          where tm.id = tournament_matchup_rounds.matchup_id and tp.user_id = auth.uid()));
create policy "creator can modify matchups" on tournament_matchups for all using (
  exists (select 1 from tournaments t where t.id = tournament_matchups.tournament_id and t.creator_user_id = auth.uid()));
create policy "members can read matchups" on tournament_matchups for select using (
  exists (select 1 from tournament_players tp where tp.tournament_id = tp.tournament_id and tp.user_id = auth.uid()));
create policy tp_delete on tournament_players for delete using (auth.uid() = (select creator_user_id from tournaments where id = tournament_players.tournament_id));
create policy tp_insert on tournament_players for insert with check (auth.uid() = (select creator_user_id from tournaments where id = tournament_players.tournament_id));
create policy tp_select on tournament_players for select using (user_id = auth.uid()
  or auth.uid() = (select creator_user_id from tournaments where id = tournament_players.tournament_id) or is_tournament_member(tournament_id));
create policy tp_update on tournament_players for update using (user_id = auth.uid()
  or auth.uid() = (select creator_user_id from tournaments where id = tournament_players.tournament_id));
create policy "creator can modify teams" on tournament_teams for all using (
  exists (select 1 from tournaments t where t.id = tournament_teams.tournament_id and t.creator_user_id = auth.uid()));
create policy "members can read teams" on tournament_teams for select using (
  exists (select 1 from tournaments t where t.id = tournament_teams.tournament_id and (t.creator_user_id = auth.uid() or
    exists (select 1 from tournament_players tp where tp.tournament_id = t.id and tp.user_id = auth.uid()))));
create policy t_delete on tournaments for delete using (creator_user_id = auth.uid());
create policy t_insert on tournaments for insert with check (creator_user_id = auth.uid());
create policy t_select on tournaments for select using (creator_user_id = auth.uid() or is_tournament_member(id));
create policy t_update on tournaments for update using (creator_user_id = auth.uid());

grant all on all tables in schema public to anon, authenticated;
