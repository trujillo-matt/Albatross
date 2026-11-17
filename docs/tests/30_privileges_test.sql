-- After 006: signed-out clients cannot call RPC or trigger functions, signed-in users still can, and the public
-- standings function stays open. RLS helper functions stay callable so signed-out reads return nothing, not errors.
set role anon;
do $$ begin
  perform b.expect_error($q$select cast_captain_votes(gen_random_uuid(), array[gen_random_uuid(), gen_random_uuid()])$q$, 'permission denied');
  perform b.expect_error($q$select draft_pick(gen_random_uuid(), gen_random_uuid())$q$, 'permission denied');
  perform b.expect_error($q$select set_hole_score(gen_random_uuid(), 1, 4)$q$, 'permission denied');
  perform b.expect_error($q$select set_pairings(gen_random_uuid(), '{}', '{}')$q$, 'permission denied');
  perform b.expect_error($q$select * from admin_code_status(gen_random_uuid())$q$, 'permission denied');
  perform b.expect_error($q$select set_spectator_link(gen_random_uuid(), true)$q$, 'permission denied');
  perform b.expect_error($q$select tp_guard_update()$q$, 'permission denied');
  perform b.assert(get_public_standings('x') is null, 'public standings still open to anon');
  -- signed-out reads must return nothing, not raise (policies call the helper functions as anon)
  perform b.assert((select count(*) from tournament_players) = 0, 'anon read returns zero rows without error');
  perform b.assert((select count(*) from tournament_captain_votes) = 0, 'anon vote read returns zero rows');
end $$;
reset role;
set role authenticated;
select b.as_user(22);
do $$ begin
  perform b.expect_error($q$select compute_matchup_result(gen_random_uuid())$q$, 'permission denied');
  perform b.expect_error($q$select trg_round_completed()$q$, 'permission denied');
  -- still callable by a signed-in user (fails on its own validation, not on privilege)
  perform b.expect_error($q$select cast_captain_votes(gen_random_uuid(), array[gen_random_uuid(), gen_random_uuid()])$q$, 'voting is not open');
end $$;
reset role;
