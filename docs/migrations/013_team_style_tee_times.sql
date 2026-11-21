-- 013: team colour and name, and tee times.
--
-- Team style: a team gets an optional colour (#RRGGBB). The name column already exists. The team's captain or any
-- admin changes either through set_team_style, which checks who is asking and writes the audit log.
--
-- Tee times: one time per player per session, set by an admin through set_tee_times. Players with the same time
-- play in the same group. Members of the tournament can read them.
begin;

alter table tournament_teams add column if not exists color text;
do $$ begin
  alter table tournament_teams add constraint tournament_teams_color_check
    check (color is null or color ~ '^#[0-9A-Fa-f]{6}$');
exception when duplicate_object then null; end $$;

create or replace function set_team_style(p_team uuid, p_name text, p_color text default null)
returns void language plpgsql security definer set search_path = public as $$
declare t tournament_teams%rowtype; clean text := btrim(coalesce(p_name, ''));
begin
  select * into t from tournament_teams where id = p_team for update;
  if not found then raise exception 'team not found'; end if;
  if auth.uid() is null or not (is_tournament_admin(t.tournament_id) or t.captain_user_id = auth.uid()) then
    raise exception 'only an admin or the team captain can change the team';
  end if;
  if char_length(clean) not between 1 and 30 then raise exception 'the team name must be 1 to 30 characters'; end if;
  if p_color is not null and p_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'the colour must look like #006747'; end if;
  if exists (select 1 from tournament_teams x where x.tournament_id = t.tournament_id and x.id <> t.id
              and lower(x.name) = lower(clean)) then
    raise exception 'the other team already has that name';
  end if;
  update tournament_teams set name = clean, color = upper(p_color) where id = p_team;
  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after)
  values (t.tournament_id, auth.uid(), 'set_team_style', 'team', p_team,
          jsonb_build_object('name', t.name, 'color', t.color), jsonb_build_object('name', clean, 'color', upper(p_color)));
end $$;

create table if not exists tournament_tee_times (
  session_id    uuid not null references tournament_sessions(id) on delete cascade,
  tournament_id uuid not null references tournaments(id) on delete cascade,
  user_id       uuid not null,
  tee_time      timestamptz not null,
  primary key (session_id, user_id)
);
create index if not exists tournament_tee_times_tournament on tournament_tee_times (tournament_id);

alter table tournament_tee_times enable row level security;
drop policy if exists tee_times_select on tournament_tee_times;
create policy tee_times_select on tournament_tee_times for select to authenticated
  using (is_tournament_member(tournament_id)
         or exists (select 1 from tournaments t where t.id = tournament_id and t.creator_user_id = auth.uid()));
revoke insert, update, delete on tournament_tee_times from anon, authenticated;
revoke all on tournament_tee_times from anon;

-- p_times is a JSON array of {"user_id": uuid, "tee_time": ISO timestamp or null}. A null time clears that player's
-- tee time. Only accepted players of the tournament can be given one.
create or replace function set_tee_times(p_session uuid, p_times jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare s tournament_sessions%rowtype; item jsonb; uid uuid; tt timestamptz; changed int := 0;
begin
  select * into s from tournament_sessions where id = p_session;
  if not found then raise exception 'session not found'; end if;
  if auth.uid() is null or not is_tournament_admin(s.tournament_id) then
    raise exception 'only an admin can set tee times';
  end if;
  if jsonb_typeof(p_times) <> 'array' then raise exception 'tee times must be a list'; end if;
  for item in select * from jsonb_array_elements(p_times) loop
    uid := (item ->> 'user_id')::uuid;
    if not exists (select 1 from tournament_players tp
                    where tp.tournament_id = s.tournament_id and tp.user_id = uid and tp.invite_status = 'accepted') then
      raise exception 'that player is not in this tournament';
    end if;
    if item ->> 'tee_time' is null or item ->> 'tee_time' = '' then
      delete from tournament_tee_times where session_id = p_session and user_id = uid;
    else
      tt := (item ->> 'tee_time')::timestamptz;
      insert into tournament_tee_times (session_id, tournament_id, user_id, tee_time)
      values (p_session, s.tournament_id, uid, tt)
      on conflict (session_id, user_id) do update set tee_time = excluded.tee_time;
    end if;
    changed := changed + 1;
  end loop;
  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, after)
  values (s.tournament_id, auth.uid(), 'set_tee_times', 'session', p_session, jsonb_build_object('players', changed));
end $$;

revoke execute on function set_team_style(uuid, text, text), set_tee_times(uuid, jsonb) from public, anon;
grant execute on function set_team_style(uuid, text, text), set_tee_times(uuid, jsonb) to authenticated;

do $$ begin
  alter publication supabase_realtime add table tournament_tee_times;
exception when duplicate_object then null; end $$;

commit;
