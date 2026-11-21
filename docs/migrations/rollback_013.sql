-- Rollback for 013: removes team colours and tee times. Team names stay as they are.
begin;
drop function if exists set_tee_times(uuid, jsonb);
drop function if exists set_team_style(uuid, text, text);
drop table if exists tournament_tee_times;
alter table tournament_teams drop constraint if exists tournament_teams_color_check;
alter table tournament_teams drop column if exists color;
commit;
