-- 009: one person keeps score for the whole group.
--
-- A "group" is the players in one match (up to 4). One of them, the scorer, enters everyone's strokes on their own
-- phone. Players volunteer with set_scorer(match, themselves) before play; an organizer can assign or change the scorer
-- at any time. The scorer gets a card per player (or one per side in scramble and alternate shot), writes strokes with
-- set_hole_score exactly as before, and finishes all cards together. While a scorer is set, nobody else can change the
-- group's cards, so two phones never fight over one scorecard. Results still come from the existing trigger.
--
-- Uses tournament_matchups.scorer_user_id, added (unused) by migration 002.
begin;

-- Who is keeping score for a match. Security definer so the guard below can ask without needing to read the matchup.
create or replace function matchup_scorer(p_matchup uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select scorer_user_id from tournament_matchups where id = p_matchup
$$;

-- Volunteer (p_scorer = yourself), step down (p_scorer = null while you are the scorer), or, for an organizer, assign
-- anyone playing in the match or clear it.
create or replace function set_scorer(p_matchup uuid, p_scorer uuid default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  me uuid := auth.uid();
  is_adm boolean;
  i_play boolean;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  if m.status = 'pending' then raise exception 'pairings are not set yet'; end if;
  if m.status = 'complete' then raise exception 'match is already complete'; end if;

  is_adm := is_tournament_admin(m.tournament_id);
  i_play := me = any (m.team_a_player_ids) or me = any (m.team_b_player_ids);

  if not is_adm and not i_play then raise exception 'only players in this match can keep score'; end if;
  if p_scorer is not null and not (p_scorer = any (m.team_a_player_ids) or p_scorer = any (m.team_b_player_ids)) then
    raise exception 'the scorer must be playing in this match';
  end if;

  if not is_adm then
    if p_scorer is not null then
      if p_scorer <> me then raise exception 'you can only volunteer yourself'; end if;
      if m.scorer_user_id is not null and m.scorer_user_id <> me then raise exception 'someone is already keeping score'; end if;
    elsif m.scorer_user_id is distinct from me then
      raise exception 'only the current scorer can step down';
    end if;
  end if;

  update tournament_matchups set scorer_user_id = p_scorer, updated_at = now() where id = p_matchup;
  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after)
  values (m.tournament_id, me, 'set_scorer', 'matchup', p_matchup, to_jsonb(m.scorer_user_id), to_jsonb(p_scorer));
end $$;

-- Creates the group's cards (idempotent). One per player; one per side for scramble and alternate shot, owned by the
-- first player listed on that side. p_course carries what the web or iOS client knows about the course:
-- {"course_name", "course_id", "pars", "handicaps", "yardages", "rating", "slope"}; all optional.
create or replace function start_group_scoring(p_matchup uuid, p_course jsonb default '{}'::jsonb)
returns table (out_round uuid, out_owner uuid, out_side text)
language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  me uuid := auth.uid();
  owners uuid[];
  o uuid;
  rid uuid;
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  if m.status <> 'active' then raise exception 'the match is not open for scoring'; end if;
  if not (m.scorer_user_id = me or is_tournament_admin(m.tournament_id)) then
    raise exception 'only the scorer can start the group scorecards';
  end if;

  if m.match_type in ('scramble', 'alternate_shot') then
    owners := array_remove(array[m.team_a_player_ids[1], m.team_b_player_ids[1]], null);
  else
    owners := m.team_a_player_ids || m.team_b_player_ids;
  end if;
  if coalesce(array_length(owners, 1), 0) = 0 then raise exception 'no players are paired for this match'; end if;

  foreach o in array owners loop
    select id into rid from rounds where matchup_id = p_matchup and user_id = o limit 1;
    if rid is null then
      rid := gen_random_uuid();
      insert into rounds (id, user_id, course_name, course_id, course_pars, course_handicaps, course_yardages,
                          course_rating, slope_rating, date, scores, status, matchup_id)
      values (rid, o, coalesce(nullif(p_course->>'course_name', ''), 'Tournament Match'), nullif(p_course->>'course_id', ''),
              nullif(p_course->'pars', 'null'::jsonb), nullif(p_course->'handicaps', 'null'::jsonb), nullif(p_course->'yardages', 'null'::jsonb),
              nullif(p_course->>'rating', '')::numeric, nullif(p_course->>'slope', '')::int,
              now(), to_jsonb(array_fill(null::int, array[18])), 'in_progress', p_matchup);
    end if;
    insert into tournament_matchup_rounds (matchup_id, round_id, user_id) values (p_matchup, rid, o)
      on conflict (matchup_id, user_id) do nothing;
  end loop;

  return query
    select r.id, r.user_id, case when r.user_id = any (m.team_a_player_ids) then 'A' else 'B' end
      from rounds r where r.matchup_id = p_matchup and r.user_id = any (owners)
     order by 3, 2;
end $$;

-- Same function as before, one new rule: the owner of a card writes it unless somebody else is keeping score for that
-- match, and the scorer can write any card in the match they score.
create or replace function set_hole_score(p_round uuid, p_hole int, p_strokes int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_hole not between 1 and 18 then raise exception 'hole must be 1 to 18'; end if;
  if p_strokes is not null and p_strokes not between 1 and 20 then
    raise exception 'strokes must be 1 to 20';
  end if;
  update rounds r
     set scores = jsonb_set(r.scores, array[(p_hole - 1)::text], coalesce(to_jsonb(p_strokes), 'null'::jsonb)),
         updated_at = now()
   where r.id = p_round and r.status = 'in_progress'
     and (
       (r.user_id = auth.uid() and (matchup_scorer(r.matchup_id) is null or matchup_scorer(r.matchup_id) = auth.uid()))
       or (r.matchup_id is not null and matchup_scorer(r.matchup_id) = auth.uid())
     );
  if not found then raise exception 'round not found, not yours, or already completed'; end if;
end $$;

-- Submits every card in the group at once. The scorer (or an organizer) only, and only when every card has 18 holes.
create or replace function finish_group_scoring(p_matchup uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype;
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  select * into m from tournament_matchups where id = p_matchup for update;
  if not found then raise exception 'matchup not found'; end if;
  if m.status <> 'active' then raise exception 'the match is not open for scoring'; end if;
  if not (m.scorer_user_id = me or is_tournament_admin(m.tournament_id)) then
    raise exception 'only the scorer can submit the group scorecards';
  end if;
  if not exists (select 1 from rounds where matchup_id = p_matchup) then raise exception 'no scorecards have been started'; end if;
  if exists (select 1 from rounds r where r.matchup_id = p_matchup and r.status = 'in_progress'
               and exists (select 1 from jsonb_array_elements(r.scores) e where e = 'null'::jsonb)) then
    raise exception 'every scorecard needs all 18 holes';
  end if;
  -- The existing trigger computes the result once the last card completes.
  update rounds set status = 'completed', updated_at = now() where matchup_id = p_matchup and status = 'in_progress';
end $$;

-- While a scorer is set, a client cannot change the group's cards unless it is the scorer. Runs as the calling role, so
-- the definer functions above (which run as the owner) pass straight through.
create or replace function rounds_scorer_guard() returns trigger language plpgsql set search_path = public as $$
declare sc uuid;
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if new.matchup_id is null then return new; end if;
  sc := matchup_scorer(new.matchup_id);
  if sc is null or sc = auth.uid() then return new; end if;
  if tg_op = 'INSERT' then raise exception 'a scorer is keeping score for this group'; end if;
  if new.scores is distinct from old.scores or new.status is distinct from old.status then
    raise exception 'a scorer is keeping score for this group';
  end if;
  return new;
end $$;
drop trigger if exists rounds_scorer_guard on rounds;
create trigger rounds_scorer_guard before insert or update on rounds
  for each row execute function rounds_scorer_guard();

-- Same least-privilege posture as 006: signed-in users only.
revoke execute on function matchup_scorer(uuid), set_scorer(uuid, uuid), start_group_scoring(uuid, jsonb),
  finish_group_scoring(uuid), rounds_scorer_guard() from public, anon;
grant execute on function matchup_scorer(uuid), set_scorer(uuid, uuid), start_group_scoring(uuid, jsonb),
  finish_group_scoring(uuid) to authenticated;
-- set_hole_score keeps the grants it already has (create or replace does not reset them).

commit;
