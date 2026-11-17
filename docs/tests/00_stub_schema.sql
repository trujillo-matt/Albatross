-- STUB of the Supabase pieces and the tables the iOS app is inferred to use. For local testing only.
-- It is NOT your real schema: no RLS on the existing tables (real policies are unknown), and column
-- types are my best inference from the Swift code. Differences between this and production are exactly
-- what the first staging run of the migrations will reveal.
create role anon nologin; create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema public, auth to anon, authenticated;
-- Supabase grants client roles access to every new public table and relies on RLS to restrict it. Mirror that
-- so the RLS negative tests check the real defense, not an accident of missing grants.
alter default privileges in schema public grant all on tables to anon, authenticated;

create table profiles (id uuid primary key, display_name text not null, username text, avatar_url text);
create table tournaments (
  id uuid primary key default gen_random_uuid(), name text not null, creator_user_id uuid not null references profiles(id),
  status text not null default 'setup', match_type text not null default 'best_ball', total_matches int not null default 3,
  points_to_win numeric not null default 9.5, created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table tournament_courses (id uuid primary key default gen_random_uuid(), tournament_id uuid not null references tournaments(id) on delete cascade,
  course_name text not null, round_number int not null, match_type text);
create table tournament_teams (id uuid primary key default gen_random_uuid(), tournament_id uuid not null references tournaments(id) on delete cascade,
  name text not null, captain_user_id uuid references profiles(id));
create table tournament_players (id uuid primary key default gen_random_uuid(), tournament_id uuid not null references tournaments(id) on delete cascade,
  user_id uuid not null references profiles(id), team_id uuid references tournament_teams(id), invite_status text not null default 'pending',
  is_admin boolean not null default false, draft_position int, unique (tournament_id, user_id));
create table tournament_captain_votes (id uuid primary key default gen_random_uuid(), tournament_id uuid not null references tournaments(id) on delete cascade,
  voter_user_id uuid not null references profiles(id), nominee_user_id uuid not null references profiles(id));
create table tournament_matchups (id uuid primary key default gen_random_uuid(), tournament_id uuid not null references tournaments(id) on delete cascade,
  matchup_number int not null, team_a_id uuid not null references tournament_teams(id), team_b_id uuid not null references tournament_teams(id),
  team_a_player_ids uuid[] not null default '{}', team_b_player_ids uuid[] not null default '{}', match_type text not null,
  status text not null default 'pending', result text, points_team_a numeric not null default 0, points_team_b numeric not null default 0);
create table rounds (id uuid primary key, user_id uuid not null references profiles(id), course_name text not null, scores jsonb not null,
  status text not null default 'in_progress', matchup_id uuid, updated_at timestamptz not null default now());
create table tournament_matchup_rounds (id uuid primary key default gen_random_uuid(), matchup_id uuid not null references tournament_matchups(id) on delete cascade,
  round_id uuid not null references rounds(id) on delete cascade, user_id uuid not null references profiles(id), unique (matchup_id, round_id));
grant all on all tables in schema public to anon, authenticated;
