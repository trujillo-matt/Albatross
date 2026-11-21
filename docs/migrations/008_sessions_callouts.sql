-- 008: sessions and captain callouts.
-- A tournament is days; a day is sessions; a session is one format and N matches. N comes from the roster
-- (floor(smaller team / players per side)), never typed in. Extra players sit out. Before each session the
-- system auto-fills a lineup, then the captains take turns calling out who faces whom.
-- Matchups created before this migration keep session_id = null and behave exactly as before.

begin;

-- New format: alternate shot (2 per side, one ball, one card per team, scored like scramble).
do $$ declare c text; begin
  for c in select conname from pg_constraint
            where conrelid = 'tournaments'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%match_type%'
  loop execute format('alter table tournaments drop constraint %I', c); end loop;
end $$;
alter table tournaments add constraint tournaments_match_type_check
  check (match_type in ('scramble','best_ball','match_play','stroke_play','alternate_shot'));

create table if not exists tournament_sessions (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  day_number int not null check (day_number >= 1),
  session_number int not null default 1 check (session_number >= 1),
  label text,
  match_type text not null check (match_type in ('scramble','best_ball','match_play','stroke_play','alternate_shot')),
  course_name text,
  course_id text,
  match_count int not null default 0,
  status text not null default 'pending' check (status in ('pending','lineup','callouts','locked','complete')),
  first_caller_team_id uuid references tournament_teams(id),
  turn_team_id uuid references tournament_teams(id),
  consecutive_passes int not null default 0,
  created_at timestamptz not null default now(),
  unique (tournament_id, day_number, session_number)
);
alter table tournament_sessions enable row level security;
drop policy if exists "members can read sessions" on tournament_sessions;
create policy "members can read sessions" on tournament_sessions for select using (
  is_tournament_member(tournament_id) or is_tournament_creator(tournament_id));
-- The creator plans the days (inserts/edits sessions) while the tournament is in setup or draft, and only as 'pending'.
-- After that, every write goes through the security definer functions below.
drop policy if exists "creator plans sessions before start" on tournament_sessions;
create policy "creator plans sessions before start" on tournament_sessions for all
  using (is_tournament_creator(tournament_id)
         and exists (select 1 from tournaments x where x.id = tournament_id and x.status in ('setup', 'draft')))
  with check (status = 'pending' and is_tournament_creator(tournament_id)
         and exists (select 1 from tournaments x where x.id = tournament_id and x.status in ('setup', 'draft')));

alter table tournament_matchups add column if not exists session_id uuid references tournament_sessions(id) on delete cascade;
alter table tournament_matchups add column if not exists called_by_team_id uuid references tournament_teams(id);
alter table tournament_matchups add column if not exists called_at timestamptz;   -- not null = locked in

do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table tournament_sessions;
    exception when duplicate_object then null; end;
  end if;
end $$;

-- Backfill: each existing course row becomes a one-session day. Existing matchups stay session_id = null.
insert into tournament_sessions (tournament_id, day_number, session_number, match_type, course_name, course_id, status)
select c.tournament_id, c.round_number, 1, coalesce(c.match_type, t.match_type), c.course_name, c.course_id, 'locked'
  from tournament_courses c join tournaments t on t.id = c.tournament_id
 where t.status in ('active', 'complete')
on conflict do nothing;

create or replace function players_per_side(p_type text) returns int language sql immutable as $$
  select case when p_type in ('match_play', 'stroke_play') then 1 else 2 end $$;

-- Teams of a tournament, side A first.
create or replace function _team_ids(p_tournament uuid, out team_a uuid, out team_b uuid) language sql stable as $$
  select (select id from tournament_teams where tournament_id = p_tournament order by side nulls last, name, id limit 1),
         (select id from tournament_teams where tournament_id = p_tournament order by side nulls last, name, id offset 1 limit 1) $$;

-- Locks a session: every match becomes playable.
create or replace function _lock_session(p_session uuid) returns void language plpgsql security definer set search_path = public as $$
begin
  update tournament_matchups set called_at = coalesce(called_at, now()), status = 'active', updated_at = now()
   where session_id = p_session and status = 'pending';
  update tournament_sessions set status = 'locked', turn_team_id = null where id = p_session;
end $$;

-- Auto-fills a session's lineup. Internal: callers check permissions.
-- Sit-outs: whoever has played the most locked matches sits, so rest is spread evenly.
-- Pairs: each player is paired with the teammate they have partnered least.
create or replace function _autofill_session(p_session uuid) returns void language plpgsql security definer set search_path = public as $$
declare
  s tournament_sessions%rowtype;
  pps int; team record;
  playing uuid[]; units uuid[][]; x uuid; y uuid; rest uuid[];
  a_units jsonb := '[]'; b_units jsonb := '[]'; res jsonb;
  n int; i int; best_count int; c int; best uuid;
begin
  select * into s from tournament_sessions where id = p_session;
  pps := players_per_side(s.match_type);
  n := s.match_count * pps;

  for team in select id, row_number() over (order by side nulls last, name, id) rn
                from tournament_teams where tournament_id = s.tournament_id order by side nulls last, name, id limit 2
  loop
    -- players on the team, least-played first, then by draft order
    select coalesce(array_agg(user_id order by played, coalesce(draft_position, 9999), user_id), '{}') into playing
      from (select tp.user_id, tp.draft_position,
                   (select count(*) from tournament_matchups m join tournament_sessions ms on ms.id = m.session_id
                     where m.tournament_id = s.tournament_id and ms.id <> s.id and ms.status in ('locked','complete')
                       and tp.user_id = any (m.team_a_player_ids || m.team_b_player_ids)) played
              from tournament_players tp
             where tp.tournament_id = s.tournament_id and tp.team_id = team.id and tp.invite_status = 'accepted') q;
    playing := playing[1:n];
    -- put the chosen players back into draft order so match 1 is the top of the draft
    select array_agg(u order by coalesce(tp.draft_position, 9999), u) into playing
      from unnest(playing) u join tournament_players tp on tp.user_id = u and tp.tournament_id = s.tournament_id;

    res := '[]'::jsonb;
    if pps = 1 then
      select coalesce(jsonb_agg(jsonb_build_array(u)), '[]') into res from unnest(playing) u;
    else
      rest := playing;
      while coalesce(array_length(rest, 1), 0) >= 2 loop
        x := rest[1]; best := null; best_count := null;
        for i in 2..array_length(rest, 1) loop
          y := rest[i];
          select count(*) into c from tournament_matchups m
           where m.tournament_id = s.tournament_id and m.session_id is not null
             and ((m.team_a_player_ids @> array[x, y]) or (m.team_b_player_ids @> array[x, y]));
          if best_count is null or c < best_count then best := y; best_count := c; end if;
        end loop;
        res := res || jsonb_build_array(jsonb_build_array(x, best));
        rest := array_remove(array_remove(rest, x), best);
      end loop;
    end if;
    if team.rn = 1 then a_units := res; else b_units := res; end if;
  end loop;

  update tournament_matchups m set
         team_a_player_ids = coalesce((select array_agg(e::uuid) from jsonb_array_elements_text(a_units -> (q.i - 1)::int) e), '{}'),
         team_b_player_ids = coalesce((select array_agg(e::uuid) from jsonb_array_elements_text(b_units -> (q.i - 1)::int) e), '{}'),
         called_by_team_id = null, called_at = null, status = 'pending', updated_at = now()
    from (select id, row_number() over (order by matchup_number) i from tournament_matchups where session_id = p_session) q
   where m.id = q.id;
  update tournament_sessions set status = 'lineup', consecutive_passes = 0, turn_team_id = null, first_caller_team_id = null
   where id = p_session;
end $$;

-- Creates every match of every session from the rosters and opens the first session.
create or replace function start_tournament(p_tournament uuid) returns void language plpgsql security definer set search_path = public as $$
declare
  t tournaments%rowtype; ta uuid; tb uuid; na int; nb int; s record; k int; num int := 0; first_session uuid;
begin
  if not is_tournament_admin(p_tournament) then raise exception 'only an admin can start the tournament'; end if;
  select * into t from tournaments where id = p_tournament for update;
  if t.status <> 'draft' then raise exception 'tournament is not in the draft stage'; end if;
  if exists (select 1 from tournament_matchups where tournament_id = p_tournament) then raise exception 'already started'; end if;
  select team_a, team_b into ta, tb from _team_ids(p_tournament);
  if ta is null or tb is null then raise exception 'both teams must exist'; end if;

  -- Tournaments created before sessions existed: one session per course row.
  if not exists (select 1 from tournament_sessions where tournament_id = p_tournament) then
    insert into tournament_sessions (tournament_id, day_number, session_number, match_type, course_name, course_id)
    select p_tournament, round_number, 1, coalesce(match_type, t.match_type), course_name, course_id
      from tournament_courses where tournament_id = p_tournament;
  end if;
  if not exists (select 1 from tournament_sessions where tournament_id = p_tournament) then
    insert into tournament_sessions (tournament_id, day_number, session_number, match_type)
    values (p_tournament, 1, 1, t.match_type);
  end if;

  select count(*) into na from tournament_players where tournament_id = p_tournament and team_id = ta and invite_status = 'accepted';
  select count(*) into nb from tournament_players where tournament_id = p_tournament and team_id = tb and invite_status = 'accepted';

  for s in select * from tournament_sessions where tournament_id = p_tournament order by day_number, session_number loop
    k := least(na, nb) / players_per_side(s.match_type);
    if k < 1 then raise exception 'each team needs at least % players for % play', players_per_side(s.match_type), s.match_type; end if;
    update tournament_sessions set match_count = k where id = s.id;
    for i in 1..k loop
      num := num + 1;
      insert into tournament_matchups (tournament_id, matchup_number, team_a_id, team_b_id, match_type, session_id)
      values (p_tournament, num, ta, tb, s.match_type, s.id);
    end loop;
    first_session := coalesce(first_session, s.id);
  end loop;

  update tournaments set status = 'active', total_matches = num, points_to_win = floor(num / 2.0) + 0.5, updated_at = now()
   where id = p_tournament;
  perform _autofill_session(first_session);
end $$;

create or replace function _can_manage_team(p_tournament uuid, p_team uuid) returns boolean language sql stable security definer set search_path = public as $$
  select is_tournament_admin(p_tournament)
      or exists (select 1 from tournament_teams where id = p_team and tournament_id = p_tournament and captain_user_id = auth.uid()) $$;

create or replace function autofill_session(p_session uuid) returns void language plpgsql security definer set search_path = public as $$
declare s tournament_sessions%rowtype;
begin
  select * into s from tournament_sessions where id = p_session for update;
  if not found then raise exception 'session not found'; end if;
  if not (is_tournament_admin(s.tournament_id) or exists (select 1 from tournament_teams
        where tournament_id = s.tournament_id and captain_user_id = auth.uid())) then
    raise exception 'only an admin or a captain can auto-fill';
  end if;
  if s.status <> 'lineup' then raise exception 'the lineup can only be changed before callouts begin'; end if;
  perform _autofill_session(p_session);
end $$;

-- A captain (or admin) sets one team's lineup for the session: p_units is [[uuid,...],...], one unit per match in order.
create or replace function set_session_side(p_session uuid, p_team uuid, p_units jsonb) returns void language plpgsql security definer set search_path = public as $$
declare
  s tournament_sessions%rowtype; pps int; ta uuid; tb uuid; ids uuid[]; flat uuid[]; mids uuid[]; i int;
begin
  select * into s from tournament_sessions where id = p_session for update;
  if not found then raise exception 'session not found'; end if;
  if not _can_manage_team(s.tournament_id, p_team) then raise exception 'only an admin or that team''s captain can set its lineup'; end if;
  if s.status <> 'lineup' then raise exception 'the lineup can only be changed before callouts begin'; end if;
  select team_a, team_b into ta, tb from _team_ids(s.tournament_id);
  if p_team not in (ta, tb) then raise exception 'unknown team'; end if;
  pps := players_per_side(s.match_type);
  if jsonb_typeof(p_units) <> 'array' or jsonb_array_length(p_units) <> s.match_count then
    raise exception 'expected % matches', s.match_count;
  end if;
  select array_agg(id order by matchup_number) into mids from tournament_matchups where session_id = p_session;
  select array_agg(e::uuid) into flat from jsonb_array_elements(p_units) u, jsonb_array_elements_text(u) e;
  if coalesce(array_length(flat, 1), 0) <> s.match_count * pps or (select count(distinct x) from unnest(flat) x) <> array_length(flat, 1) then
    raise exception 'each match needs % distinct players per side', pps;
  end if;
  if (select count(*) from tournament_players where tournament_id = s.tournament_id and team_id = p_team
        and invite_status = 'accepted' and user_id = any (flat)) <> array_length(flat, 1) then
    raise exception 'players must belong to the team';
  end if;
  for i in 1..s.match_count loop
    if jsonb_array_length(p_units -> (i - 1)) <> pps then raise exception 'each match needs % players per side', pps; end if;
    if p_team = ta then
      update tournament_matchups set team_a_player_ids = (select array_agg(e::uuid) from jsonb_array_elements_text(p_units -> (i - 1)) e), updated_at = now() where id = mids[i];
    else
      update tournament_matchups set team_b_player_ids = (select array_agg(e::uuid) from jsonb_array_elements_text(p_units -> (i - 1)) e), updated_at = now() where id = mids[i];
    end if;
  end loop;
end $$;

-- Starts the callout round. First caller: the trailing team; level means A, B, A... by session order. Admin may choose.
create or replace function open_callouts(p_session uuid, p_first_caller uuid default null) returns void language plpgsql security definer set search_path = public as $$
declare
  s tournament_sessions%rowtype; ta uuid; tb uuid; pa numeric; pb numeric; first_team uuid; idx int; pps int;
begin
  select * into s from tournament_sessions where id = p_session for update;
  if not found then raise exception 'session not found'; end if;
  if not (is_tournament_admin(s.tournament_id) or exists (select 1 from tournament_teams
        where tournament_id = s.tournament_id and captain_user_id = auth.uid())) then
    raise exception 'only an admin or a captain can open callouts';
  end if;
  if s.status <> 'lineup' then raise exception 'session is not in the lineup stage'; end if;
  pps := players_per_side(s.match_type);
  if exists (select 1 from tournament_matchups where session_id = p_session
              and (coalesce(array_length(team_a_player_ids, 1), 0) <> pps or coalesce(array_length(team_b_player_ids, 1), 0) <> pps)) then
    raise exception 'every match needs a full lineup first';
  end if;
  select team_a, team_b into ta, tb from _team_ids(s.tournament_id);
  select coalesce(sum(points_team_a), 0), coalesce(sum(points_team_b), 0) into pa, pb
    from tournament_matchups where tournament_id = s.tournament_id;
  if p_first_caller is not null and is_tournament_admin(s.tournament_id) and p_first_caller in (ta, tb) then
    first_team := p_first_caller;
  elsif pa < pb then first_team := ta;
  elsif pb < pa then first_team := tb;
  else
    select count(*) into idx from tournament_sessions
     where tournament_id = s.tournament_id and (day_number, session_number) < (s.day_number, s.session_number);
    first_team := case when idx % 2 = 0 then ta else tb end;
  end if;
  update tournament_sessions set status = 'callouts', first_caller_team_id = first_team, turn_team_id = first_team, consecutive_passes = 0
   where id = p_session;
  -- a single-match session has nothing to call out
  if s.match_count <= 1 then perform _lock_session(p_session); end if;
end $$;

-- The captain whose turn it is names one of their own units and the opposing unit they want to face.
-- Their unit takes the opponent's slot; the unit that was there moves into the slot the caller left. The called slot locks.
create or replace function make_callout(p_session uuid, p_my_unit uuid[], p_their_unit uuid[], p_override boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  s tournament_sessions%rowtype; ta uuid; tb uuid; me_a boolean; mine tournament_matchups%rowtype; theirs tournament_matchups%rowtype;
  mine_unit uuid[]; theirs_mine uuid[]; open_left int; last_id uuid;
begin
  select * into s from tournament_sessions where id = p_session for update;
  if not found then raise exception 'session not found'; end if;
  if s.status <> 'callouts' then raise exception 'callouts are not open'; end if;
  if not (exists (select 1 from tournament_teams where id = s.turn_team_id and captain_user_id = auth.uid())
          or (p_override and is_tournament_admin(s.tournament_id))) then
    raise exception 'not your turn';
  end if;
  select team_a, team_b into ta, tb from _team_ids(s.tournament_id);
  me_a := s.turn_team_id = ta;

  select * into mine from tournament_matchups where session_id = p_session and called_at is null
     and (case when me_a then team_a_player_ids else team_b_player_ids end) @> p_my_unit
     and (case when me_a then team_a_player_ids else team_b_player_ids end) <@ p_my_unit;
  if not found then raise exception 'that unit is not available'; end if;
  select * into theirs from tournament_matchups where session_id = p_session and called_at is null
     and (case when me_a then team_b_player_ids else team_a_player_ids end) @> p_their_unit
     and (case when me_a then team_b_player_ids else team_a_player_ids end) <@ p_their_unit;
  if not found then raise exception 'that opponent is not available'; end if;

  if mine.id <> theirs.id then
    theirs_mine := case when me_a then theirs.team_a_player_ids else theirs.team_b_player_ids end;
    mine_unit := case when me_a then mine.team_a_player_ids else mine.team_b_player_ids end;
    if me_a then
      update tournament_matchups set team_a_player_ids = theirs_mine, updated_at = now() where id = mine.id;
      update tournament_matchups set team_a_player_ids = mine_unit, updated_at = now() where id = theirs.id;
    else
      update tournament_matchups set team_b_player_ids = theirs_mine, updated_at = now() where id = mine.id;
      update tournament_matchups set team_b_player_ids = mine_unit, updated_at = now() where id = theirs.id;
    end if;
  end if;
  update tournament_matchups set called_by_team_id = s.turn_team_id, called_at = now() where id = theirs.id;

  select count(*), min(id::text)::uuid into open_left, last_id from tournament_matchups where session_id = p_session and called_at is null;
  if open_left <= 1 then
    perform _lock_session(p_session);      -- the last match has no choice left
  else
    update tournament_sessions set turn_team_id = case when me_a then tb else ta end, consecutive_passes = 0 where id = p_session;
  end if;
end $$;

-- Passing hands over the turn. Two passes in a row lock whatever is left as it stands.
create or replace function pass_callout(p_session uuid, p_override boolean default false) returns void language plpgsql security definer set search_path = public as $$
declare s tournament_sessions%rowtype; ta uuid; tb uuid;
begin
  select * into s from tournament_sessions where id = p_session for update;
  if not found then raise exception 'session not found'; end if;
  if s.status <> 'callouts' then raise exception 'callouts are not open'; end if;
  if not (exists (select 1 from tournament_teams where id = s.turn_team_id and captain_user_id = auth.uid())
          or (p_override and is_tournament_admin(s.tournament_id))) then
    raise exception 'not your turn';
  end if;
  select team_a, team_b into ta, tb from _team_ids(s.tournament_id);
  if s.consecutive_passes + 1 >= 2 then
    perform _lock_session(p_session);
  else
    update tournament_sessions set consecutive_passes = consecutive_passes + 1,
           turn_team_id = case when turn_team_id = ta then tb else ta end where id = p_session;
  end if;
end $$;

-- set_pairings stays as the admin override. Captains are refused while a session is in callouts, and sides must fit the format.
create or replace function set_pairings(p_matchup uuid, p_team_a uuid[], p_team_b uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare m tournament_matchups%rowtype; ok boolean; adm boolean; ss text; pps int;
begin
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  adm := is_tournament_admin(m.tournament_id);
  select adm or exists (select 1 from tournament_teams where id in (m.team_a_id, m.team_b_id) and captain_user_id = auth.uid())
    into ok;
  if not ok then raise exception 'only an admin or a captain can set pairings'; end if;
  if m.status = 'complete' then raise exception 'match is already complete'; end if;
  if m.session_id is not null then
    select status into ss from tournament_sessions where id = m.session_id;
    if ss = 'callouts' and not adm then raise exception 'callouts are in progress'; end if;
  end if;
  if coalesce(array_length(p_team_a, 1), 0) not between 1 and 2
     or coalesce(array_length(p_team_a, 1), 0) <> coalesce(array_length(p_team_b, 1), 0) then
    raise exception 'pick the same number of players (1 or 2) on each side';
  end if;
  -- Matches that belong to a session must also fit their format. Older matches keep the 1-or-2 rule.
  pps := players_per_side(m.match_type);
  if m.session_id is not null and array_length(p_team_a, 1) <> pps then
    raise exception 'pick % player(s) on each side for this format', pps;
  end if;
  if (select count(*) from tournament_players where tournament_id = m.tournament_id and team_id = m.team_a_id
        and invite_status = 'accepted' and user_id = any (p_team_a)) <> array_length(p_team_a, 1)
     or (select count(*) from tournament_players where tournament_id = m.tournament_id and team_id = m.team_b_id
        and invite_status = 'accepted' and user_id = any (p_team_b)) <> array_length(p_team_b, 1) then
    raise exception 'players must belong to the team they are paired for';
  end if;
  update tournament_matchups set team_a_player_ids = p_team_a, team_b_player_ids = p_team_b,
         status = case when m.session_id is null or ss in ('locked','complete') then 'active' else m.status end,
         updated_at = now() where id = p_matchup;
end $$;

-- compute_matchup_result: alternate shot counts like scramble; finishing a session opens the next.
create or replace function compute_matchup_result(p_matchup uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  t tournaments%rowtype;
  n_a int; n_b int;
  pa numeric; pb numeric;
  a_total int; b_total int;
  a_holes numeric := 0; b_holes numeric := 0;
  v_result text;
  tot_a numeric; tot_b numeric; all_done boolean; v_next uuid;
begin
  -- Row lock serializes concurrent finishers so the result is written once.
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then return; end if;
  select * into t from tournaments where id = m.tournament_id;

  create temporary table if not exists _mr (side text, round_id uuid, scores jsonb) on commit drop;
  truncate _mr;
  insert into _mr
  select case when l.user_id = any (m.team_a_player_ids) then 'A'
              when l.user_id = any (m.team_b_player_ids) then 'B' end,
         r.id, r.scores
    from tournament_matchup_rounds l
    join rounds r on r.id = l.round_id
   where l.matchup_id = p_matchup and r.status = 'completed';
  delete from _mr where side is null;

  select count(*) filter (where side = 'A'), count(*) filter (where side = 'B') into n_a, n_b from _mr;

  -- Ready check: scramble needs one card per team, others one per paired player.
  if m.match_type in ('scramble', 'alternate_shot') then
    if n_a < 1 or n_b < 1 then return; end if;
  else
    if n_a + n_b < coalesce(array_length(m.team_a_player_ids, 1), 0) + coalesce(array_length(m.team_b_player_ids, 1), 0) then
      return;
    end if;
  end if;

  if m.match_type = 'match_play' then
    select coalesce(sum(case when a < b then 1 when a = b then 0.5 else 0 end), 0),
           coalesce(sum(case when b < a then 1 when a = b then 0.5 else 0 end), 0)
      into a_holes, b_holes
      from (select h,
                   (select min((s.scores ->> h)::int) from _mr s where s.side = 'A') a,
                   (select min((s.scores ->> h)::int) from _mr s where s.side = 'B') b
              from generate_series(0, 17) h) x
     where a is not null and b is not null;
    if a_holes > b_holes then pa := 1; pb := 0;
    elsif b_holes > a_holes then pa := 0; pb := 1;
    else pa := 0.5; pb := 0.5; end if;

  elsif m.match_type in ('best_ball', 'scramble', 'alternate_shot') then
    select coalesce(sum(a), 0), coalesce(sum(b), 0) into a_total, b_total
      from (select (select min((s.scores ->> h)::int) from _mr s where s.side = 'A') a,
                   (select min((s.scores ->> h)::int) from _mr s where s.side = 'B') b
              from generate_series(0, 17) h) x;
    -- Swift sums each side independently, skipping holes with no score for that side.
    if a_total < b_total then pa := 1; pb := 0;
    elsif b_total < a_total then pa := 0; pb := 1;
    else pa := 0.5; pb := 0.5; end if;

  else -- stroke_play: lowest single-player total per side
    select coalesce(min(tot) filter (where side = 'A'), 2147483647),
           coalesce(min(tot) filter (where side = 'B'), 2147483647)
      into a_total, b_total
      from (select side,
                   (select coalesce(sum((e.v)::int), 0)
                      from jsonb_array_elements_text(s.scores) with ordinality e(v, i)
                     where e.v is not null and e.v <> 'null') tot
              from _mr s) x;
    if a_total < b_total then pa := 1; pb := 0;
    elsif b_total < a_total then pa := 0; pb := 1;
    else pa := 0.5; pb := 0.5; end if;
  end if;

  v_result := case when pa > pb then 'team_a_win' when pb > pa then 'team_b_win' else 'tie' end;
  update tournament_matchups
     set status = 'complete', result = v_result, points_team_a = pa, points_team_b = pb
   where id = p_matchup;

  select coalesce(sum(points_team_a), 0), coalesce(sum(points_team_b), 0), bool_and(status = 'complete')
    into tot_a, tot_b, all_done
    from tournament_matchups where tournament_id = m.tournament_id;
  if tot_a >= t.points_to_win or tot_b >= t.points_to_win or all_done then
    update tournaments set status = 'complete', updated_at = now() where id = m.tournament_id;
  end if;
  -- When the last match of a session finishes, close it and open the next one with a fresh auto-filled lineup.
  if m.session_id is not null
     and not exists (select 1 from tournament_matchups where session_id = m.session_id and status <> 'complete') then
    update tournament_sessions set status = 'complete' where id = m.session_id;
    if (select status from tournaments where id = m.tournament_id) <> 'complete' then
      select n.id into v_next from tournament_sessions n, tournament_sessions c
       where c.id = m.session_id and n.tournament_id = c.tournament_id and n.status = 'pending'
         and (n.day_number, n.session_number) > (c.day_number, c.session_number)
       order by n.day_number, n.session_number limit 1;
      if v_next is not null then perform _autofill_session(v_next); end if;
    end if;
  end if;
end $$;

-- Privileges, matching 006: RPCs for signed-in users only, internal helpers for nobody (they run inside the RPCs as owner).
revoke execute on function start_tournament(uuid), autofill_session(uuid), set_session_side(uuid, uuid, jsonb),
  open_callouts(uuid, uuid), make_callout(uuid, uuid[], uuid[], boolean), pass_callout(uuid, boolean),
  set_pairings(uuid, uuid[], uuid[]) from public, anon;
grant execute on function start_tournament(uuid), autofill_session(uuid), set_session_side(uuid, uuid, jsonb),
  open_callouts(uuid, uuid), make_callout(uuid, uuid[], uuid[], boolean), pass_callout(uuid, boolean),
  set_pairings(uuid, uuid[], uuid[]) to authenticated;
revoke execute on function _autofill_session(uuid), _lock_session(uuid), _can_manage_team(uuid, uuid), _team_ids(uuid)
  from public, anon, authenticated;

commit;
