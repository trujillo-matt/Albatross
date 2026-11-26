# Sessions and captain callouts: project context

Handoff notes for a Claude Code project. Everything here was done and checked in one session on 2026-11-20. Items marked [Unverified] were not confirmed.

## Goal

The tournaments feature focused on one match between pairings. The scope should be the day. A tournament is days, a day is sessions, a session is one format, and the number of matches comes from the roster size, never typed in. The main focus is captain matchup callouts. Reference formats: Ryder Cup (two teams, match play, foursomes/fourball/singles sessions, 14.5 to win) and the Internet Invitational (scramble then alternate shot, team eliminations).

## Decisions made with the user

- Cover both the Next.js web app and the iOS app.
- Each day has 1 to 3 sessions, each with its own format.
- Players are auto-filled into a lineup and stay editable.
- Uneven rosters: extras sit out (matches = floor(smaller team / players per side)).
- "Callouts" means captains take turns calling out who faces whom.
- Apply to the live Supabase project, not a branch. A branch attempt was declined, and main has no recorded migrations, so a branch would have started empty.
- Merge to main (fast-forward), because production deploys from main.

## Repo map

- iOS: `Albatross/` (SwiftUI, Supabase Swift SDK). Xcode project uses synchronized folders, so new files are picked up automatically.
- Web: `web/` (Next.js 14, TypeScript, Tailwind). Vercel project `albatross-tournaments`, team `truj-soft`.
- DB: Supabase project `rtcyetcyhdrajvcstvlj` (Albatross, us-east-1). Migrations in `docs/migrations/001` to `008` plus `rollback_*`. Test schema stub: `docs/tests/00_stub_schema.sql`.
- Earlier design docs: `docs/TOURNAMENT_WEB_APP_PLAN.md`, `docs/LIVE_SCHEMA_AUDIT.md`.

## What was built (commit 088a282)

Database, `docs/migrations/008_sessions_callouts.sql`:
- Table `tournament_sessions` (day_number, session_number, label, match_type, course, match_count, status pending/lineup/callouts/locked/complete, turn_team_id, consecutive_passes). RLS on. Members and creator read. The creator may insert or edit only while the tournament is setup or draft, and only with status pending.
- `tournament_matchups` gained `session_id`, `called_by_team_id`, `called_at` (not null means locked in). Matches with null `session_id` use the old behavior.
- New format `alternate_shot`: 2 per side, one card per team, scored like scramble.
- RPCs: `start_tournament`, `autofill_session`, `set_session_side`, `open_callouts`, `make_callout`, `pass_callout`. Helpers: `_autofill_session`, `_lock_session`, `_can_manage_team`, `_team_ids`, `players_per_side`.
- `set_pairings` kept as the admin override. Captains are refused while a session is in callouts, and session matches must fit the format's side size.
- `compute_matchup_result` extended for alternate shot, and when a session's last match finishes it completes the session and auto-fills the next one.

Rules:
- Match count per session = floor(smaller team / players per side). Singles formats are 1 per side, pairs formats 2.
- Points to win = floor(total matches / 2) + 0.5.
- Auto-fill: players who have played the most locked matches sit out first, ties by draft position. Pairs are matched with the teammate they have partnered least.
- First caller: the trailing team. When level, alternate A, B, A by session order. An admin may override.
- A callout: the caller names one of their units and the opposing unit they want. Their unit takes the opponent's slot, and the displaced unit moves into the slot the caller left. The called match locks. The last open match locks automatically. Two passes in a row lock the rest as they stand.
- Locking sets matches to `active`. Matches stay `pending` until then, so scoring cannot start early in the clients.

Web:
- `web/lib/sessions.ts` (pure logic) with `sessions.test.ts`; `components/CalloutBoard.tsx` and `DayBoard.tsx`.
- Create form builds days and sessions with presets and a match-count preview.
- Admin Matches tab, player hub and standings are grouped by day and session.
- Course lookup goes through `courseForMatch`, replacing the old "round_number equals matchup_number" guess.

iOS:
- `TournamentSession` model, `alternateShot`, session fields on matchups, `Tournament.days` grouped by session.
- Store RPC wrappers; `startTournament` now calls the RPC; optional afternoon session per day in `NewTournamentSheet`.
- New screen `Views/Tournament/TournamentSessionsView.swift`, linked from the active tournament as "Lineups & Callouts".

## State of deployment

- Migration 008 applied to the live Supabase project via the Supabase connector (`apply_migration`, name `sessions_callouts`). Checked afterward: table, RLS, 2 policies, columns, 11 functions, privileges (anon cannot call the RPCs), realtime, format check.
- Branch `claude/upbeat-gauss-0rweso` pushed. `main` fast-forwarded from 09f8b52 to 088a282.
- Vercel production deployment `dpl_5SYSsUcpjs8JeUcZEayYsgYunS7X` reached READY, alias albatross-tournaments.vercel.app. Rollback candidate: `dpl_6iUZoWQh9oCu6t7TXEFoTebbEdKu`.
- The live site was not opened in a browser.
- iOS: not built, and the new Swift code has never been compiled. This environment has no Swift toolchain. Expect possible compile errors, so build in Xcode first.

## Verification that was run

- SQL: `docs/tests/run.sh` against a scratch Postgres 16. All suites pass, including new `50_sessions_callouts_test.sql`. It needs a data directory the `postgres` OS user can reach (used `/tmp/pgscratch`, port 5544).
- Web: `npm test` 25 pass, `npx tsc --noEmit` clean, `npm run test:e2e` 4 pass (legacy paths only).

## Known gaps and caveats

- No browser e2e for the callout flow, and no Swift unit tests.
- `get_public_standings` (spectator link) does not group by session.
- Scoring is blocked before lock only by the clients (matches stay pending). The database does not enforce it for a direct API write.
- Not built: eliminations, redrafts, playoff tiebreaks, bonus holes.
- The one live tournament was already active with 3 legacy matches (null `session_id`). The backfill added 3 `locked` session rows for it, so the web Overview lists them as Day 1 to 3. They can be deleted if unwanted.
- `rollback_008.sql` drops the new objects but does not restore `compute_matchup_result` and `set_pairings`. Restore those from 002 and 005.

## Gotchas found

- Node's test runner needs `.ts` extensions on value imports in `web/lib` (tsconfig already allows them).
- In PL/pgSQL, a loop variable or declared record with the same name as a SQL alias causes "ambiguous" or "not assigned" errors.
- `row_number()` is bigint; cast before using it as a jsonb array index.
- Swift: avoid `optional.map(set.contains)` (ambiguous overload); use a closure.
- `web/node_modules` is gitignored; run `npm install` in `web/` first.

## User preferences

- No em dashes in anything written.
- Label unverified claims, state confidence plainly, and report failures and skipped steps as they are.
- Commit and push only on the designated branch unless told otherwise. No PRs unless asked.
