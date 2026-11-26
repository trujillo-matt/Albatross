-- 016: tournament news reports lead changes in match play.
-- A lead change is the sign of "holes up" flipping, or a lead going back to all square, once at least 3 holes are
-- decided. Only match play has holes up; the other formats are stroke totals and are left out. Holes up uses the same
-- rule as the apps: for each hole, each side's best score, counted over holes both sides have scored.
-- Only a trigger sees a score before and after it changes, so this cannot be derived by the clients later.
begin;

alter table tournament_news drop constraint if exists tournament_news_kind_check;
alter table tournament_news add constraint tournament_news_kind_check
  check (kind in ('ace', 'eagle', 'birdie', 'score_change', 'match_result', 'lead_change'));

-- Holes up (side A's view) and holes decided for a match, with one card's scores swapped for p_scores.
create or replace function match_play_status(p_matchup uuid, p_round uuid, p_scores jsonb)
returns table (up int, thru int) language sql stable set search_path = public as $$
  with m as (select team_a_player_ids a_ids, team_b_player_ids b_ids from tournament_matchups where id = p_matchup),
  cards as (
    select case when r.user_id = any (m.a_ids) then 'A' when r.user_id = any (m.b_ids) then 'B' end side,
           case when r.id = p_round then p_scores else r.scores end sc
      from rounds r, m where r.matchup_id = p_matchup
  ),
  holes as (
    select (select min((c.sc ->> h)::int) from cards c where c.side = 'A') a,
           (select min((c.sc ->> h)::int) from cards c where c.side = 'B') b
      from generate_series(0, 17) h
  )
  select coalesce(sum(case when a < b then 1 when b < a then -1 else 0 end), 0)::int, count(*)::int
    from holes where a is not null and b is not null
$$;

create or replace function news_on_lead_change() returns trigger language plpgsql security definer set search_path = public as $$
declare m tournament_matchups%rowtype; before_s record; after_s record; who text; hl text;
begin
  if new.matchup_id is null or new.scores is not distinct from old.scores then return new; end if;
  select * into m from tournament_matchups where id = new.matchup_id;
  if not found or m.match_type <> 'match_play' then return new; end if;
  select * into before_s from match_play_status(m.id, new.id, old.scores);
  select * into after_s from match_play_status(m.id, new.id, new.scores);
  if sign(before_s.up) = sign(after_s.up) or after_s.thru < 3 then return new; end if;
  if after_s.up = 0 then
    hl := 'Match ' || m.matchup_number || ' is back to all square through ' || after_s.thru;
  else
    select name into who from tournament_teams where id = case when after_s.up > 0 then m.team_a_id else m.team_b_id end;
    hl := coalesce(who, case when after_s.up > 0 then 'Team A' else 'Team B' end) || ' took the lead in match '
          || m.matchup_number || ', ' || abs(after_s.up) || ' up through ' || after_s.thru;
  end if;
  insert into tournament_news (tournament_id, matchup_id, kind, headline) values (m.tournament_id, m.id, 'lead_change', hl);
  return new;
end $$;

drop trigger if exists news_lead_change on rounds;
create trigger news_lead_change after update of scores on rounds
  for each row execute function news_on_lead_change();

revoke execute on function news_on_lead_change() from public, anon, authenticated;
revoke execute on function match_play_status(uuid, uuid, jsonb) from public, anon, authenticated;

commit;
