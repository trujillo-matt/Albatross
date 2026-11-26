-- Rollback for 020: no admin_remove_player. Players already removed stay removed (their rows keep invite_status 'declined').
begin;
drop function if exists admin_remove_player(uuid, uuid, text);
commit;
