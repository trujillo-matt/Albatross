-- Rollback for 016: removes lead-change news. Existing lead_change rows are deleted so the old constraint holds.
begin;
drop trigger if exists news_lead_change on rounds;
drop function if exists news_on_lead_change();
drop function if exists match_play_status(uuid, uuid, jsonb);
delete from tournament_news where kind = 'lead_change';
alter table tournament_news drop constraint if exists tournament_news_kind_check;
alter table tournament_news add constraint tournament_news_kind_check
  check (kind in ('ace', 'eagle', 'birdie', 'score_change', 'match_result'));
commit;
