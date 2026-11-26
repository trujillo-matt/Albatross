-- 020: an admin can remove a player after the draft has started (adding goes through the admin-players edge function).
--
-- The player's row stays with invite_status 'declined' and no team, so names in finished matches and the history keep
-- resolving, and every roster screen (which lists accepted players) no longer shows them. Their login codes are revoked
-- and their tee times for sessions that have not finished are cleared. The removal is audited with the reason given.
--
-- Refused, with a message that says what to do first:
--   * the organizer who created the tournament;
--   * a team captain (the captain would have to be replaced, which is not supported yet);
--   * a player who is in a match that has not finished: move them out with Edit matches (set_pairings) first, so no
--     match is left with a missing player.
-- A finished match keeps the player in its history.
begin;

create or replace function admin_remove_player(p_tournament uuid, p_user uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  t tournaments%rowtype;
  tp tournament_players%rowtype;
  open_match int;
begin
  select * into t from tournaments where id = p_tournament;
  if not found then raise exception 'tournament not found'; end if;
  if auth.uid() is null or not is_tournament_admin(p_tournament) then raise exception 'admin only'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason required'; end if;

  select * into tp from tournament_players where tournament_id = p_tournament and user_id = p_user for update;
  if not found or tp.invite_status <> 'accepted' then raise exception 'that player is not on the roster'; end if;
  if p_user = t.creator_user_id then raise exception 'the organizer cannot be removed'; end if;
  if exists (select 1 from tournament_teams where tournament_id = p_tournament and captain_user_id = p_user) then
    raise exception 'a captain cannot be removed';
  end if;

  select min(m.matchup_number) into open_match
    from tournament_matchups m
   where m.tournament_id = p_tournament and m.status <> 'complete'
     and p_user = any (coalesce(m.team_a_player_ids, '{}') || coalesce(m.team_b_player_ids, '{}'));
  if open_match is not null then
    raise exception 'they are in match % which has not finished; move them out with Edit matches first', open_match;
  end if;

  update tournament_players set invite_status = 'declined', team_id = null, draft_position = null
   where tournament_id = p_tournament and user_id = p_user;
  update player_access_codes set status = 'revoked', revoked_at = now()
   where tournament_id = p_tournament and user_id = p_user and status = 'active';
  delete from tournament_tee_times tt
   using tournament_sessions s
   where tt.session_id = s.id and tt.tournament_id = p_tournament and tt.user_id = p_user and s.status <> 'complete';

  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after, reason)
  values (p_tournament, auth.uid(), 'remove_player', 'player', p_user,
          jsonb_build_object('team_id', tp.team_id, 'invite_status', tp.invite_status), jsonb_build_object('invite_status', 'declined'), p_reason);
end $$;

revoke execute on function admin_remove_player(uuid, uuid, text) from public, anon;
grant execute on function admin_remove_player(uuid, uuid, text) to authenticated;

commit;
