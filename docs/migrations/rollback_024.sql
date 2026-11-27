-- Rollback for 024: no Live Activity pushes. Alerts (022, 023) are untouched.
begin;
drop trigger if exists live_activity_score on rounds;
drop trigger if exists live_activity_queue_kick on live_activity_queue;
drop function if exists live_activity_on_score();
drop function if exists live_activity_queue_kick();
drop function if exists claim_live_activity_matchups(int);
drop function if exists match_live_status(uuid);
drop function if exists register_live_activity_token(uuid, text);
drop function if exists unregister_live_activity_token(text);
drop table if exists live_activity_queue;
drop table if exists live_activity_tokens;
commit;
