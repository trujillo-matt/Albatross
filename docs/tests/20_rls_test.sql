-- Runs AFTER 005 (and after 05_demonstrate_bugs.sql seeded tournaments X and Y). Each block is the fixed version
-- of a bug that 05 proved real, plus checks that legitimate access still works.
insert into auth.users (id) select b.u(i) from generate_series(27, 28) i;
insert into tournament_players (tournament_id, user_id, invite_status, team_id) values
  ('aaaaaaaa-0000-4000-8000-000000000001', b.u(26), 'pending',  null),                                   -- invitee, has not answered
  ('aaaaaaaa-0000-4000-8000-000000000001', b.u(27), 'accepted', 'a2000000-0000-4000-8000-000000000001'); -- on team B
update tournament_teams set captain_user_id = b.u(27) where id = 'a2000000-0000-4000-8000-000000000001';   -- 27 captains team B, so is not a pick
insert into tournament_captain_votes (tournament_id, voter_user_id, nominee_user_id) values
  ('aaaaaaaa-0000-4000-8000-000000000001', b.u(22), b.u(25));
insert into rounds (id, user_id, course_name, date, scores, status, matchup_id) values
  ('dddddddd-0000-4000-8000-000000000002', b.u(24), 'C', now(), '[5,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null]', 'in_progress',
   'cccccccc-0000-4000-8000-000000000002');   -- a card in tournament Y

create function b.expect_error(sql text, pattern text) returns void language plpgsql as $$
begin
  begin
    execute sql;
  exception when others then
    if sqlerrm !~* pattern then raise exception 'wrong error for [%]: got "%" expected /%/', sql, sqlerrm, pattern; end if;
    return;
  end;
  raise exception 'EXPECTED AN ERROR matching /%/ but the statement succeeded: %', pattern, sql;
end $$;

set role authenticated;
select b.as_user(22);   -- captain of team A in tournament X, member of X only

do $$ begin
  -- 1. leak closed; own tournament still readable
  perform b.assert((select count(*) from tournament_captain_votes where tournament_id = 'bbbbbbbb-0000-4000-8000-000000000002') = 0, 'FIXED: no votes of tournament Y');
  perform b.assert((select count(*) from tournament_matchups where tournament_id = 'bbbbbbbb-0000-4000-8000-000000000002') = 0, 'FIXED: no matchups of tournament Y');
  perform b.assert((select count(*) from tournament_captain_votes where tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 1, 'own tournament votes still readable');
  perform b.assert((select count(*) from tournament_matchups where tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 1, 'own tournament matchups still readable');
end $$;

do $$ begin
  -- 2. no self promotion or self move
  perform b.expect_error($q$update tournament_players set is_admin = true where user_id = b.u(22)$q$, 'only answer their own invite');
  perform b.expect_error($q$update tournament_players set team_id = 'a2000000-0000-4000-8000-000000000001' where user_id = b.u(22)$q$, 'only answer their own invite');
  perform b.expect_error($q$update tournament_players set draft_position = 1 where user_id = b.u(22)$q$, 'only answer their own invite');
  perform b.assert((select not is_admin from tournament_players where user_id = b.u(22) and tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'still not admin');
end $$;

select b.as_user(26);   -- pending invitee
do $$ begin
  update tournament_players set invite_status = 'accepted' where user_id = b.u(26);
  perform b.assert((select invite_status from tournament_players where user_id = b.u(26) and tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 'accepted', 'an invitee can still accept');
  perform b.expect_error($q$update tournament_players set invite_status = 'declined' where user_id = b.u(26)$q$, 'invalid invite change');
  perform b.expect_error($q$update tournament_players set is_admin = true where user_id = b.u(26)$q$, 'only answer their own invite');
end $$;

select b.as_user(21);   -- creator
do $$ begin
  update tournament_players set is_admin = true, draft_position = 3 where user_id = b.u(25) and tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001';
  perform b.assert((select is_admin from tournament_players where user_id = b.u(25) and tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001'), 'creator may still edit anything');
  update tournament_players set is_admin = false where user_id = b.u(25) and tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001';
end $$;

select b.as_user(22);
do $$ begin
  -- 3. the captain can now draft through draft_pick (direct update stays blocked)
  perform draft_pick('aaaaaaaa-0000-4000-8000-000000000001', b.u(25));
  perform b.assert((select team_id from tournament_players where user_id = b.u(25) and tournament_id = 'aaaaaaaa-0000-4000-8000-000000000001') = 'a1000000-0000-4000-8000-000000000001',
    'FIXED: captain drafted a player');
  -- and pairings through set_pairings
  perform b.expect_error($q$select set_pairings('cccccccc-0000-4000-8000-000000000001', array[b.u(25), b.u(22)], array[b.u(27)])$q$, 'same number');
  perform b.expect_error($q$select set_pairings('cccccccc-0000-4000-8000-000000000001', array[b.u(27)], array[b.u(25)])$q$, 'belong to the team');
  perform set_pairings('cccccccc-0000-4000-8000-000000000001', array[b.u(25)], array[b.u(27)]);
  perform b.assert((select status from tournament_matchups where id = 'cccccccc-0000-4000-8000-000000000001') = 'active', 'FIXED: captain set pairings');
end $$;

select b.as_user(25);   -- a team A player, not a captain
do $$ begin
  perform b.expect_error($q$select set_pairings('cccccccc-0000-4000-8000-000000000001', array[b.u(25)], array[b.u(27)])$q$, 'admin or a captain');
end $$;
select b.as_user(24);   -- member of tournament Y only
do $$ begin
  perform b.expect_error($q$select set_pairings('cccccccc-0000-4000-8000-000000000001', array[b.u(25)], array[b.u(27)])$q$, 'admin or a captain');
end $$;

select b.as_user(22);
do $$ begin
  -- 4. names of co-members visible, strangers not
  perform b.assert((select count(*) from profiles where id in (b.u(21), b.u(25), b.u(27))) = 3, 'FIXED: co-member profiles readable');
  perform b.assert((select count(*) from profiles where id = b.u(24)) = 0, 'strangers in other tournaments stay hidden');
  -- 5. in-progress cards of the same tournament visible, other tournament's not
  perform b.assert((select count(*) from rounds where id = 'dddddddd-0000-4000-8000-000000000001') = 1, 'FIXED: co-member in-progress card readable');
  perform b.assert((select count(*) from rounds where id = 'dddddddd-0000-4000-8000-000000000002') = 0, 'other tournament card stays hidden');
  -- cards outside tournaments are still private until completed
  perform b.assert((select count(*) from rounds where matchup_id is null and status = 'in_progress') = 0, 'ordinary in-progress rounds stay private');
end $$;

select b.as_user(25);
do $$ begin
  -- 6. the columns iOS already sends now exist
  insert into rounds (id, user_id, course_name, date, scores, course_rating, slope_rating)
  values (gen_random_uuid(), b.u(25), 'Pebble', now(), '[]', 75.5, 145);
end $$;

-- signed out
select set_config('request.jwt.claim.sub', '', false);
do $$ begin
  perform b.assert((select count(*) from tournament_players) = 0, 'signed-out client sees no players');
  perform b.assert((select count(*) from profiles) = 0, 'signed-out client sees no profiles');
end $$;
reset role;
