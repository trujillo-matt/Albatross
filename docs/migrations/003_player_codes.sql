-- Managed players, access codes, audit log, and admin helper functions for the web app.
--
-- STATUS: NOT APPLIED and NOT TESTED. Apply after 001 and 002, against a staging copy first.
-- Assumes profiles(id, display_name, ...) exists as the iOS app uses it.

begin;

alter table profiles add column if not exists is_managed boolean not null default false;
alter table profiles add column if not exists managed_by uuid references profiles(id);
alter table profiles add column if not exists claimed_at timestamptz;

create table if not exists player_access_codes (
  id               uuid primary key default gen_random_uuid(),
  tournament_id    uuid not null references tournaments(id) on delete cascade,
  user_id          uuid not null references profiles(id) on delete cascade,
  code_hash        text not null unique,
  code_hint        text,
  status           text not null default 'active' check (status in ('active', 'revoked', 'expired')),
  expires_at       timestamptz,
  failed_attempts  int not null default 0,
  last_used_at     timestamptz,
  created_by       uuid not null references profiles(id),
  created_at       timestamptz not null default now(),
  revoked_at       timestamptz
);
create unique index if not exists player_access_codes_one_active
  on player_access_codes (tournament_id, user_id) where status = 'active';

create table if not exists code_redeem_attempts (
  id         uuid primary key default gen_random_uuid(),
  ip_hash    text not null,
  success    boolean not null,
  created_at timestamptz not null default now()
);
create index if not exists code_redeem_attempts_ip on code_redeem_attempts (ip_hash, created_at desc);

create table if not exists tournament_audit_log (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  actor_user_id uuid,
  action        text not null,
  target_type   text,
  target_id     uuid,
  before        jsonb,
  after         jsonb,
  reason        text,
  created_at    timestamptz not null default now()
);

-- These tables are only reachable through the edge functions (service role) and the
-- security definer functions below. RLS on, no policies = no direct client access.
alter table player_access_codes enable row level security;
alter table code_redeem_attempts enable row level security;
alter table tournament_audit_log enable row level security;

create or replace function is_tournament_admin(p_tournament uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from tournaments t where t.id = p_tournament and t.creator_user_id = auth.uid())
      or exists (select 1 from tournament_players p
                  where p.tournament_id = p_tournament and p.user_id = auth.uid() and p.is_admin);
$$;

-- Code status for the admin roster. Never returns the hash.
create or replace function admin_code_status(p_tournament uuid)
returns table (user_id uuid, status text, code_hint text, last_used_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_tournament_admin(p_tournament) then raise exception 'admin only'; end if;
  return query
    select c.user_id, c.status, c.code_hint, c.last_used_at
      from player_access_codes c
     where c.tournament_id = p_tournament
       and c.created_at = (select max(c2.created_at) from player_access_codes c2
                            where c2.tournament_id = c.tournament_id and c2.user_id = c.user_id);
end $$;

-- Audited admin score edit (works on locked cards).
create or replace function admin_set_hole_score(p_round uuid, p_hole int, p_strokes int, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_tournament uuid;
  v_before jsonb;
begin
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason required'; end if;
  if p_hole not between 1 and 18 then raise exception 'hole must be 1 to 18'; end if;
  if p_strokes is not null and p_strokes not between 1 and 20 then raise exception 'strokes must be 1 to 20'; end if;

  select m.tournament_id, r.scores into v_tournament, v_before
    from rounds r
    join tournament_matchups m on m.id = r.matchup_id
   where r.id = p_round;
  if v_tournament is null then raise exception 'round is not part of a tournament'; end if;
  if not is_tournament_admin(v_tournament) then raise exception 'admin only'; end if;

  update rounds
     set scores = jsonb_set(scores, array[(p_hole - 1)::text], coalesce(to_jsonb(p_strokes), 'null'::jsonb)),
         updated_at = now()
   where id = p_round;

  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id, before, after, reason)
  values (v_tournament, auth.uid(), 'edit_hole_score', 'round', p_round, v_before,
          (select scores from rounds where id = p_round), p_reason);
end $$;

create or replace function admin_recompute_matchup(p_matchup uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_tournament uuid;
begin
  select tournament_id into v_tournament from tournament_matchups where id = p_matchup;
  if v_tournament is null or not is_tournament_admin(v_tournament) then raise exception 'admin only'; end if;
  perform compute_matchup_result(p_matchup);
  insert into tournament_audit_log (tournament_id, actor_user_id, action, target_type, target_id)
  values (v_tournament, auth.uid(), 'recompute_matchup', 'matchup', p_matchup);
end $$;

-- compute_matchup_result is only for triggers and the admin wrapper above.
revoke execute on function compute_matchup_result(uuid) from public, anon, authenticated;

commit;
