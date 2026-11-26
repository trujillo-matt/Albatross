-- 015: the public standings page can group matches by day and session.
-- Additive: every existing key stays as it was; matchups gain session_id, and a new 'sessions' array is added.
begin;
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
    'sessions', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', s.id, 'day_number', s.day_number, 'session_number', s.session_number,
                 'label', s.label, 'match_type', s.match_type, 'course_name', s.course_name, 'status', s.status)
                 order by s.day_number, s.session_number) from tournament_sessions s where s.tournament_id = v_t.id), '[]'::jsonb),
    'matchups', coalesce((select jsonb_agg(jsonb_build_object(
                 'number', m.matchup_number, 'type', m.match_type, 'status', m.status, 'session_id', m.session_id,
                 'team_a_id', m.team_a_id, 'team_b_id', m.team_b_id,
                 'points_a', m.points_team_a, 'points_b', m.points_team_b)
                 order by m.matchup_number) from tournament_matchups m where m.tournament_id = v_t.id), '[]'::jsonb)
  );
end $$;
commit;
