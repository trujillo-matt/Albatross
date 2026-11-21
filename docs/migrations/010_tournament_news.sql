-- 010: tournament news.
-- A feed of what happened in a tournament: birdies and better, corrected scores, finished matches.
-- Only triggers write to it. Members read it. Both apps show it on their home pages.
-- Entries are recorded from now on; scores entered before this migration are not back-filled.

begin;

create table if not exists tournament_news (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  matchup_id    uuid references tournament_matchups(id) on delete cascade,
  kind          text not null check (kind in ('ace', 'eagle', 'birdie', 'score_change', 'match_result')),
  player_user_id uuid,
  hole          int,
  headline      text not null,
  created_at    timestamptz not null default now()
);
create index if not exists tournament_news_recent on tournament_news (tournament_id, created_at desc);

alter table tournament_news enable row level security;
drop policy if exists news_select on tournament_news;
create policy news_select on tournament_news for select to authenticated
  using (is_tournament_member(tournament_id)
         or exists (select 1 from tournaments t where t.id = tournament_id and t.creator_user_id = auth.uid()));
revoke insert, update, delete on tournament_news from anon, authenticated;
revoke all on tournament_news from anon;

-- A score is saved on a round. Birdies, eagles and aces are news the first time a hole is scored;
-- changing a score that was already entered is news too, so a correction is never silent.
create or replace function news_on_round_scores() returns trigger language plpgsql security definer set search_path = public as $$
declare
  m tournament_matchups%rowtype; pname text; i int; o jsonb; n jsonb; strokes int; par int; k text; hl text;
begin
  if new.matchup_id is null or new.scores is not distinct from old.scores then return new; end if;
  select * into m from tournament_matchups where id = new.matchup_id;
  if not found then return new; end if;
  select coalesce(nullif(display_name, ''), 'A player') into pname from profiles where id = new.user_id;
  pname := coalesce(pname, 'A player');
  for i in 0..17 loop
    o := old.scores -> i;
    n := new.scores -> i;
    if n is null or n = 'null'::jsonb or n is not distinct from o then continue; end if;
    strokes := (n #>> '{}')::int;
    par := nullif(new.course_pars ->> i, '')::int;
    if o is null or o = 'null'::jsonb then
      if strokes = 1 then k := 'ace'; hl := pname || ' made a hole in one on hole ' || (i + 1);
      elsif par is not null and par - strokes >= 2 then k := 'eagle'; hl := pname || ' made an eagle on hole ' || (i + 1);
      elsif par is not null and par - strokes = 1 then k := 'birdie'; hl := pname || ' made a birdie on hole ' || (i + 1);
      else continue;
      end if;
    else
      k := 'score_change';
      hl := 'Score changed: ' || pname || ', hole ' || (i + 1) || ', ' || (o #>> '{}') || ' to ' || strokes;
    end if;
    insert into tournament_news (tournament_id, matchup_id, kind, player_user_id, hole, headline)
    values (m.tournament_id, m.id, k, new.user_id, i + 1, hl);
  end loop;
  return new;
end $$;

drop trigger if exists news_round_scores on rounds;
create trigger news_round_scores after update of scores on rounds
  for each row execute function news_on_round_scores();

-- A match finishes.
create or replace function news_on_match_complete() returns trigger language plpgsql security definer set search_path = public as $$
declare a text; b text; hl text;
begin
  if new.status <> 'complete' or old.status = 'complete' then return new; end if;
  select name into a from tournament_teams where id = new.team_a_id;
  select name into b from tournament_teams where id = new.team_b_id;
  hl := case
    when coalesce(new.points_team_a, 0) > coalesce(new.points_team_b, 0) then coalesce(a, 'Team A') || ' won match ' || new.matchup_number
    when coalesce(new.points_team_b, 0) > coalesce(new.points_team_a, 0) then coalesce(b, 'Team B') || ' won match ' || new.matchup_number
    else 'Match ' || new.matchup_number || ' was halved'
  end;
  insert into tournament_news (tournament_id, matchup_id, kind, headline)
  values (new.tournament_id, new.id, 'match_result', hl);
  return new;
end $$;

drop trigger if exists news_match_complete on tournament_matchups;
create trigger news_match_complete after update of status on tournament_matchups
  for each row execute function news_on_match_complete();

revoke execute on function news_on_round_scores() from public, anon, authenticated;
revoke execute on function news_on_match_complete() from public, anon, authenticated;

do $$ begin
  alter publication supabase_realtime add table tournament_news;
exception when duplicate_object then null; end $$;

commit;
