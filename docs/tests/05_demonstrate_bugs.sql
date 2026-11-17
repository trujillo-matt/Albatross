-- Runs AFTER 001 to 004 and BEFORE 005. Proves the audit findings are real against the live policies, so the
-- fixes in 005 are not fixing imaginary problems. Each block asserts the BUGGY behavior.
create schema b;
grant usage on schema b to anon, authenticated;
create function b.as_user(n int) returns void language sql as
  $$ select set_config('request.jwt.claim.sub', ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0')), false) $$;
create function b.u(n int) returns uuid language sql immutable as $$ select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $$;
create function b.assert(c boolean, m text) returns void language plpgsql as $$ begin if not coalesce(c, false) then raise exception 'EXPECTED BUG NOT FOUND: %', m; end if; end $$;

insert into auth.users (id) select b.u(i) from generate_series(21, 26) i;
-- Tournament X: user 21 creates, 22 plays.   Tournament Y: user 23 creates, 24 plays.
insert into tournaments (id, name, creator_user_id, match_type, status) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'X', b.u(21), 'best_ball', 'draft'),
  ('bbbbbbbb-0000-4000-8000-000000000002', 'Y', b.u(23), 'best_ball', 'draft');
insert into tournament_teams (id, tournament_id, name, side, captain_user_id) values
  ('a1000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'Team A', 'A', b.u(22)),
  ('a2000000-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 'Team B', 'B', null),
  ('b1000000-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000002', 'Team A', 'A', null),
  ('b2000000-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000002', 'Team B', 'B', null);
insert into tournament_players (tournament_id, user_id, invite_status, is_admin, team_id) values
  ('aaaaaaaa-0000-4000-8000-000000000001', b.u(21), 'accepted', true, null),
  ('aaaaaaaa-0000-4000-8000-000000000001', b.u(22), 'accepted', false, 'a1000000-0000-4000-8000-000000000001'),
  ('aaaaaaaa-0000-4000-8000-000000000001', b.u(25), 'accepted', false, null),
  ('bbbbbbbb-0000-4000-8000-000000000002', b.u(23), 'accepted', true, null),
  ('bbbbbbbb-0000-4000-8000-000000000002', b.u(24), 'accepted', false, null);
insert into tournament_captain_votes (tournament_id, voter_user_id, nominee_user_id) values
  ('bbbbbbbb-0000-4000-8000-000000000002', b.u(24), b.u(23));
insert into tournament_matchups (id, tournament_id, matchup_number, team_a_id, team_b_id, match_type) values
  ('cccccccc-0000-4000-8000-000000000002', 'bbbbbbbb-0000-4000-8000-000000000002', 1,
   'b1000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000002', 'best_ball');
insert into tournament_matchups (id, tournament_id, matchup_number, team_a_id, team_b_id, match_type) values
  ('cccccccc-0000-4000-8000-000000000001', 'aaaaaaaa-0000-4000-8000-000000000001', 1,
   'a1000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'best_ball');
insert into rounds (id, user_id, course_name, date, scores, status, matchup_id) values
  ('dddddddd-0000-4000-8000-000000000001', b.u(25), 'C', now(),
   '[4,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]', 'in_progress', 'cccccccc-0000-4000-8000-000000000001');

set role authenticated;
select b.as_user(22);   -- a player in tournament X only

do $$ begin
  -- BUG 1: sees tournament Y's votes and matchups
  perform b.assert((select count(*) from tournament_captain_votes where tournament_id = 'bbbbbbbb-0000-4000-8000-000000000002') = 1,
    'player in X can read votes of tournament Y');
  perform b.assert((select count(*) from tournament_matchups where tournament_id = 'bbbbbbbb-0000-4000-8000-000000000002') = 1,
    'player in X can read matchups of tournament Y');
end $$;

do $$ begin
  -- BUG 2: a player can make themselves admin
  update tournament_players set is_admin = true
   where tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001' and user_id = b.u(22);
  perform b.assert((select is_admin from tournament_players where tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001' and user_id = b.u(22)),
    'player can set own is_admin');
  -- ... and move themselves to another team
  update tournament_players set team_id = 'a2000000-0000-4000-8000-000000000001'
   where tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001' and user_id = b.u(22);
  perform b.assert((select team_id from tournament_players where tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001' and user_id = b.u(22))
    = 'a2000000-0000-4000-8000-000000000001', 'player can set own team');
end $$;

do $$ declare n int; begin
  -- BUG 3: the captain of team A cannot draft player 25 by direct update (0 rows, no error)
  update tournament_players set team_id = 'a1000000-0000-4000-8000-000000000001'
   where tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001' and user_id = b.u(25);
  get diagnostics n = row_count;
  perform b.assert(n = 0, 'captain direct update of another player is silently ignored');
end $$;

do $$ begin
  -- BUG 4: a co-member cannot read another player's profile name
  update profiles set display_name = 'Visible?' where id = b.u(22);   -- own row, allowed
  perform b.assert((select count(*) from profiles where id = b.u(21)) = 0, 'cannot read a co-member profile');
  -- BUG 5: cannot see another member's in-progress card (owner 25 is in the same tournament as 22)
  perform b.assert((select count(*) from rounds where id = 'dddddddd-0000-4000-8000-000000000001') = 0,
    'cannot read a co-member in-progress card');
end $$;
reset role;

-- leave the fixtures clean for the post-fix tests
update tournament_players set is_admin = false, team_id = 'a1000000-0000-4000-8000-000000000001'
 where tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001' and user_id = b.u(22);
