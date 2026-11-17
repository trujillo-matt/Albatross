# Live schema audit (2026-11-17)

Read-only. Two saved notebooks ("Albatross schema audit (read-only)" and "... 2") ran metadata queries against the
project: tables, columns, constraints, indexes, RLS policies, triggers, function definitions, views, realtime
publication, extensions. **No row data was read and nothing in the database was changed.** Run results are not
stored in this repo; the queries are in the notebooks.

## Where my assumptions were wrong

| Assumption (stub schema) | Reality | Effect |
|---|---|---|
| `rounds` has `course_rating`, `slope_rating` | **Columns do not exist** | The web scorecard insert would fail. The iOS app also sends them, so its sync of rated courses likely fails too **[Inference]**. Fixed in 005. |
| New vote uniqueness needed | Already enforced: `unique (tournament_id, voter_user_id, nominee_user_id)` | Duplicate index removed from 002 |
| `tournament_matchup_rounds` unique on `(matchup_id, round_id)` | Unique on **`(matchup_id, user_id)`** | Web upsert now uses `onConflict: matchup_id,user_id` |
| User columns reference `profiles` | They reference **`auth.users`** | No change needed; my new FKs to `profiles` are fine because every managed player has a profile |
| `rounds.scores` is `jsonb` | Confirmed `jsonb` | `set_hole_score` and scoring SQL are valid as written |
| Profile row created by hand | `on_auth_user_created` trigger runs `handle_new_user` (uses metadata key `full_name`) | The `admin-players` function upserts the profile explicitly, so this is safe |

## Real problems already in the live database

All reproduced against a local copy of the live schema and policies (`docs/tests/05_demonstrate_bugs.sql`).

1. **Cross-tournament data leak.** Policies `members can read votes` and `members can read matchups` compare
   `tp.tournament_id = tp.tournament_id` (always true). Any player in any tournament can read every tournament's
   captain votes and matchups.
2. **Players can promote themselves.** `tp_update` lets a player update their own `tournament_players` row with no
   column limit: `is_admin`, `team_id`, `draft_position`.
3. **Captains cannot draft or set pairings.** `tp_update` only allows self or creator, and matchups are
   creator-only. A captain's update affects 0 rows and raises no error, so the iOS draft pick and captain pairing
   very likely did nothing **[Inference from the policies, not observed in the app]**.
4. **Matchup results only saved if the commissioner finishes last.** `tournament_matchups` is creator-only, so the
   iOS client-side result write by a normal player is silently ignored **[Inference]**. The trigger in 002 fixes it.
5. **Other players' names are invisible** to anything that reads `profiles` directly (own-row policy). The iOS app
   avoids this through the `profile_with_counts` view, which exposes every profile to every signed-in user.
6. **In-progress cards of other players are unreadable**, so an admin could not see live scores.

Not changed, but worth knowing: `completed rounds are public` lets anyone, signed in or not, read every completed
round (including `user_id` and scores). That may be intended for the social feed.

## Fixes

Migration `005_rls_fixes.sql`: fixes 1, 2, 3 (via `draft_pick` and the new `set_pairings`), 5, 6, adds the two
`rounds` columns, and adds `tournament_teams` to realtime. Result calculation (4) is in `002`. The iOS app now calls
`draft_pick` and `set_pairings`. Apply order: 001, 002, 003, 004, 005.

## Decisions for you

- **Co-admins.** Table policies honor only the creator; my functions honor `is_admin` too. Co-admins can use the RPC
  based actions but not direct writes (teams, matchups, courses). Either extend those policies or treat co-admin as
  unsupported for now.
- **Existing tournaments.** Migration 002 corrects `points_to_win` for non-complete tournaments still at 9.5 with
  fewer than 18 matches.

## Applied to the live project (2026-11-17)

Migrations 001 to 006 were applied to project `rtcyetcyhdrajvcstvlj` through the Supabase connector, one at a time.
The project held no tournaments, teams or tournament rounds, so no existing data was changed (pre-flight counts: 0).

Verified afterwards with read-only queries:
- all 9 new columns, 3 new tables (row-level security on), the new constraint and indexes, and `tournament_teams`
  in realtime;
- the four replaced or added policies have the new definitions;
- the three new triggers are enabled and the existing `on_auth_user_created` trigger is untouched;
- every function body on the live project hashes identically to the locally tested copy (for
  `compute_matchup_result` the comparison is against the comment-stripped body, since comment lines were stripped
  before sending);
- who can execute what is as designed (006).

Not verified against the live project: behavior with real users and data (no end-to-end run yet), and the two edge
functions, which still need deploying. `rollback_001_to_006.sql` backs everything out.
