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

Edge functions `redeem-code` and `admin-players` are deployed (ACTIVE, version 1, gateway JWT check off because players have
no session yet and `admin-players` validates the caller's token itself). `CODE_PEPPER` is set; the first value was pasted into a
chat by mistake, so it was rotated before any code existed, using a value generated and sent without being displayed.
Smoke tests against the live functions: a wrong or malformed code returns a generic 401, `admin-players` rejects a caller
who is not signed in, GET is refused, and the CORS preflight succeeds.

Not verified against the live project: a successful code login and player creation (needs an admin sign-in), behavior with
real users and data, and the Swift changes. `rollback_001_to_006.sql` backs the database changes out.

## Live end-to-end run (2026-11-20)

The web app (production build, served locally) was driven in a real browser against the live project: admin sign-in,
create tournament, add two managed players, code login for both, captain vote, finalize captains, captain draft, start
tournament, set pairings, both players score 18 holes, result computed by the database trigger, audited admin edit,
spectator link opened signed out. The database was then checked directly: tournament complete, stroke play 1.0 to 0.0,
captains, team placement, six vote rows, both cards completed with real course pars and rating, audit rows present.
All test data was then deleted and the live database returned to its original state (one account, no tournaments).
The script is `web/tests/live/live-flow.cjs`.

**Bug found and fixed (migration 007).** Creating a managed player failed with "Database error creating new user". The
cause was a bug that already existed: `handle_new_user()` referenced `profiles` without a schema and had no pinned
`search_path`, so whenever Supabase Auth itself inserted a user (admin createUser, and by the same path public signup)
the trigger failed with `relation "profiles" does not exist`. **[Inference]** new-account signup in the iOS app may
therefore have been failing in production; this was proven for the admin path only. 007 qualifies the table and pins
the search_path, and also pins the search_path on the two trigger functions from 002.

**Not exercised in this run:** Realtime push updates (the sandbox proxy does not carry WebSockets, so the script
reloads pages instead), the offline scoring queue against the live project (covered only by the mocked browser test),
a physical phone, and the iOS app.
