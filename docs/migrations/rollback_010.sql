-- Rollback for 010: removes the tournament news feed.
begin;
drop trigger if exists news_round_scores on rounds;
drop trigger if exists news_match_complete on tournament_matchups;
drop function if exists news_on_round_scores();
drop function if exists news_on_match_complete();
drop table if exists tournament_news;
commit;
