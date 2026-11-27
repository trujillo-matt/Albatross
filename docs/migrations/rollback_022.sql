-- Rollback for 022: no push trigger, no device tokens. News itself is untouched.
begin;
drop trigger if exists news_push on tournament_news;
drop function if exists news_push_after_insert();
drop function if exists register_device_token(text, boolean);
drop function if exists unregister_device_token(text);
drop table if exists device_tokens;
alter table tournament_news drop column if exists pushed_at;
commit;
