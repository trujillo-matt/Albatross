-- Public spectator link and audit log reader.
-- STATUS: NOT APPLIED and NOT TESTED. Apply after 003.

begin;

alter table tournaments add column if not exists public_token text unique;

-- Admin turns the link on (returns the token) or off (clears it, which kills old links).
create or replace function set_spectator_link(p_tournament uuid, p_enable boolean)
returns text language plpgsql security definer set search_path = public as $$
declare v_token text;
begin
  if not is_tournament_admin(p_tournament) then raise exception 'admin only'; end if;
  if p_enable then
    update tournaments
       set public_token = coalesce(public_token, replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''))
     where id = p_tournament
    returning public_token into v_token;
  else
    update tournaments set public_token = null where id = p_tournament;
  end if;
  insert into tournament_audit_log (tournament_id, actor_user_id, action, after)
  values (p_tournament, auth.uid(), case when p_enable then 'enable_spectator_link' else 'disable_spectator_link' end, null);
  return v_token;
end $$;

-- Read-only public view: names and scores only. Callable without signing in.
create or replace function get_public_standings(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_t tournaments%rowtype;
begin
  if p_token is null or length(p_token) < 32 then return null; end if;
  select * into v_t from tournaments where public_token = p_token;
  if not found then return null; end if;
  return jsonb_build_object(
    'name', v_t.name, 'status', v_t.status, 'points_to_win', v_t.points_to_win,
    'teams', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', tm.id, 'name', tm.name, 'side', tm.side,
                 'players', coalesce((select jsonb_agg(pr.display_name order by pr.display_name)
                                        from tournament_players tp join profiles pr on pr.id = tp.user_id
                                       where tp.team_id = tm.id), '[]'::jsonb))
                 order by tm.side) from tournament_teams tm where tm.tournament_id = v_t.id), '[]'::jsonb),
    'matchups', coalesce((select jsonb_agg(jsonb_build_object(
                 'number', m.matchup_number, 'type', m.match_type, 'status', m.status,
                 'team_a_id', m.team_a_id, 'team_b_id', m.team_b_id,
                 'points_a', m.points_team_a, 'points_b', m.points_team_b)
                 order by m.matchup_number) from tournament_matchups m where m.tournament_id = v_t.id), '[]'::jsonb)
  );
end $$;
grant execute on function get_public_standings(text) to anon, authenticated;

create or replace function admin_audit_log(p_tournament uuid)
returns table (created_at timestamptz, actor_name text, action text, target_type text, reason text, before jsonb, after jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_tournament_admin(p_tournament) then raise exception 'admin only'; end if;
  return query
    select l.created_at, pr.display_name, l.action, l.target_type, l.reason, l.before, l.after
      from tournament_audit_log l left join profiles pr on pr.id = l.actor_user_id
     where l.tournament_id = p_tournament
     order by l.created_at desc limit 200;
end $$;

commit;
