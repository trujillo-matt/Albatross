-- Server-side enforcement of tournament rules, shared by the iOS and web clients.
--
-- STATUS: NOT APPLIED and NOT TESTED. Written against the schema inferred from the Swift
-- client (there is no schema file in the repo). Before running:
--   1. Compare table/column names with the live Supabase schema.
--   2. Confirm rounds.scores is jsonb (this file assumes a jsonb array of 18 nullable ints;
--      if it is int[], adapt set_hole_score and the scoring helpers).
--   3. Run on a staging copy, then run the parity tests against the Swift scoring functions.
-- Requires 001_tournament_team_side.sql (uses tournament_teams.side).

begin;

-- ---------------------------------------------------------------------------
-- Problem 1: unreachable points_to_win. Fix existing rows that kept the old 9.5 default.
-- ---------------------------------------------------------------------------
update tournaments
   set points_to_win = total_matches / 2.0 + 0.5
 where points_to_win = 9.5
   and total_matches < 18
   and status <> 'complete';

-- ---------------------------------------------------------------------------
-- Problem 7 (web): real course data per tournament round.
-- Problem 8: optional designated scorer for scramble.
-- ---------------------------------------------------------------------------
alter table tournament_courses add column if not exists course_id text;
alter table tournament_matchups add column if not exists scorer_user_id uuid references profiles(id);

-- ---------------------------------------------------------------------------
-- Problem 5: voting rules. One ballot per voter, exactly 2 distinct nominees.
-- ---------------------------------------------------------------------------
-- The unique (tournament_id, voter_user_id, nominee_user_id) constraint already exists in the live database.

-- Both writes the ballot atomically and rejects invalid ones.
-- Self-nomination is allowed (matches the iOS behavior); add a check here to forbid it.
create or replace function cast_captain_votes(p_tournament uuid, p_nominees uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from tournaments where id = p_tournament and status = 'draft') then
    raise exception 'voting is not open';
  end if;
  if not exists (select 1 from tournament_players
                  where tournament_id = p_tournament and user_id = v_me and invite_status = 'accepted') then
    raise exception 'only accepted players can vote';
  end if;
  if coalesce(array_length(p_nominees, 1), 0) <> 2 or p_nominees[1] = p_nominees[2] then
    raise exception 'pick exactly 2 different nominees';
  end if;
  if (select count(*) from tournament_players
       where tournament_id = p_tournament and invite_status = 'accepted'
         and user_id = any (p_nominees)) <> 2 then
    raise exception 'nominees must be accepted players';
  end if;
  if exists (select 1 from tournament_captain_votes
              where tournament_id = p_tournament and voter_user_id = v_me) then
    raise exception 'already voted';
  end if;
  insert into tournament_captain_votes (tournament_id, voter_user_id, nominee_user_id)
  select p_tournament, v_me, unnest(p_nominees);
end $$;

-- ---------------------------------------------------------------------------
-- Problems 2 and 4: deterministic captain selection, explicit tie handling, and captains
-- placed on their own team. Admin only. p_tiebreak lists the winners when 2nd and 3rd tie.
-- ---------------------------------------------------------------------------
create or replace function finalize_captains(p_tournament uuid, p_tiebreak uuid[] default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_ranked uuid[];
  v_counts int[];
  v_cutoff int;
  v_clear uuid[];
  v_tied uuid[];
  v_slots int;
  v_captains uuid[];
  v_team_a uuid;
  v_team_b uuid;
begin
  if not exists (select 1 from tournaments t
                  where t.id = p_tournament
                    and (t.creator_user_id = auth.uid()
                         or exists (select 1 from tournament_players p
                                     where p.tournament_id = t.id and p.user_id = auth.uid() and p.is_admin))) then
    raise exception 'admin only';
  end if;

  select array_agg(nominee_user_id order by n desc, nominee_user_id), array_agg(n order by n desc, nominee_user_id)
    into v_ranked, v_counts
    from (select nominee_user_id, count(*) n from tournament_captain_votes
           where tournament_id = p_tournament group by nominee_user_id) s;
  if coalesce(array_length(v_ranked, 1), 0) < 2 then raise exception 'not enough votes'; end if;

  v_cutoff := v_counts[2];
  select array_agg(r order by r) into v_clear
    from unnest(v_ranked) with ordinality u(r, i) where v_counts[i] > v_cutoff;
  select array_agg(r order by r) into v_tied
    from unnest(v_ranked) with ordinality u(r, i) where v_counts[i] = v_cutoff;
  v_clear := coalesce(v_clear, '{}');
  v_slots := 2 - coalesce(array_length(v_clear, 1), 0);

  if array_length(v_tied, 1) > v_slots then
    if p_tiebreak is null or coalesce(array_length(p_tiebreak, 1), 0) <> v_slots
       or not (p_tiebreak <@ v_tied) then
      raise exception 'captain_tie: choose % of %', v_slots, v_tied;
    end if;
    v_captains := v_clear || p_tiebreak;
  else
    v_captains := v_ranked[1:2];
  end if;

  select id into v_team_a from tournament_teams where tournament_id = p_tournament and side = 'A';
  select id into v_team_b from tournament_teams where tournament_id = p_tournament and side = 'B';

  update tournament_teams set captain_user_id = v_captains[1] where id = v_team_a;
  update tournament_teams set captain_user_id = v_captains[2] where id = v_team_b;
  update tournament_players set team_id = v_team_a where tournament_id = p_tournament and user_id = v_captains[1];
  update tournament_players set team_id = v_team_b where tournament_id = p_tournament and user_id = v_captains[2];
end $$;

-- ---------------------------------------------------------------------------
-- Problem 6: draft turn order enforced in the database.
-- Snake order A, B, B, A, A, B, B, A ... Captains are pre-placed and do not count as picks.
-- Admins may bypass the turn check (override) by passing p_override = true.
-- ---------------------------------------------------------------------------
create or replace function draft_pick(p_tournament uuid, p_player uuid, p_override boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_me uuid := auth.uid();
  v_my_team record;
  v_picks int;
  v_a_turn boolean;
  v_is_admin boolean;
begin
  select exists (select 1 from tournaments t where t.id = p_tournament and t.creator_user_id = v_me)
      or exists (select 1 from tournament_players p where p.tournament_id = p_tournament and p.user_id = v_me and p.is_admin)
    into v_is_admin;

  select (select count(*) from tournament_players p
           where p.tournament_id = p_tournament and p.team_id is not null
             and p.user_id not in (select captain_user_id from tournament_teams
                                    where tournament_id = p_tournament and captain_user_id is not null))
    into v_picks;
  v_a_turn := (v_picks % 4) in (0, 3);

  select * into v_my_team from tournament_teams
   where tournament_id = p_tournament and captain_user_id = v_me;

  if not (p_override and v_is_admin) then
    if v_my_team.id is null then raise exception 'not a captain'; end if;
    if (v_my_team.side = 'A') <> v_a_turn then raise exception 'not your turn'; end if;
  end if;

  update tournament_players
     set team_id = coalesce(v_my_team.id,
                            (select id from tournament_teams
                              where tournament_id = p_tournament
                                and side = case when v_a_turn then 'A' else 'B' end))
   where tournament_id = p_tournament and user_id = p_player
     and invite_status = 'accepted' and team_id is null;
  if not found then raise exception 'player not available'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- Problem 10: per-hole score writes. Updates one array element so two writers on the
-- same card do not overwrite each other's other holes. Owner only (admins edit via a
-- separate audited function in the web app).
-- ---------------------------------------------------------------------------
create or replace function set_hole_score(p_round uuid, p_hole int, p_strokes int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_hole not between 1 and 18 then raise exception 'hole must be 1 to 18'; end if;
  if p_strokes is not null and p_strokes not between 1 and 20 then
    raise exception 'strokes must be 1 to 20';
  end if;
  update rounds
     set scores = jsonb_set(scores, array[(p_hole - 1)::text],
                            coalesce(to_jsonb(p_strokes), 'null'::jsonb)),
         updated_at = now()
   where id = p_round and user_id = auth.uid() and status = 'in_progress';
  if not found then raise exception 'round not found, not yours, or already completed'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- Problem 9: result computed once, in the database, idempotently. Mirrors the Swift
-- functions in Tournament.swift (calculateMatchPlayPoints / BestBall / StrokePlay).
-- ---------------------------------------------------------------------------
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
  tot_a numeric; tot_b numeric; all_done boolean;
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
  if m.match_type = 'scramble' then
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

  elsif m.match_type in ('best_ball', 'scramble') then
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
end $$;

-- Fire on either event: iOS links the round after finishing it, so the link insert can be
-- the last piece to arrive. compute_matchup_result is idempotent and ignores not-ready matches.
create or replace function trg_round_completed() returns trigger language plpgsql security definer as $$
begin
  if new.matchup_id is not null and new.status = 'completed'
     and (tg_op = 'INSERT' or old.status is distinct from 'completed') then
    perform compute_matchup_result(new.matchup_id);
  end if;
  return new;
end $$;

drop trigger if exists rounds_completed on rounds;
create trigger rounds_completed after insert or update of status on rounds
  for each row execute function trg_round_completed();

create or replace function trg_matchup_round_linked() returns trigger language plpgsql security definer as $$
begin
  perform compute_matchup_result(new.matchup_id);
  return new;
end $$;

drop trigger if exists matchup_round_linked on tournament_matchup_rounds;
create trigger matchup_round_linked after insert on tournament_matchup_rounds
  for each row execute function trg_matchup_round_linked();

commit;
