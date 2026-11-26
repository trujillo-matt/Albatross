-- Rollback for 021: no admin_add_tiebreak. A tiebreak matchup already added stays as an ordinary match.
begin;
drop function if exists admin_add_tiebreak(uuid, uuid, uuid, text);
commit;
