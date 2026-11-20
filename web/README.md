# Albatross Tournaments (web)

Next.js 14 + TypeScript + Tailwind + Supabase. Players log scores with a code; admins run the tournament.
Shares the Supabase project with the iOS app. See `../docs/TOURNAMENT_WEB_APP_PLAN.md` for the full design.

## Status

Built, type-checked, and tested in three layers. **Migrations 001 to 007 are applied to the live Supabase project, and a full tournament has been played through the real UI against it (`docs/LIVE_SCHEMA_AUDIT.md`, `tests/live/`). The edge functions are deployed and `CODE_PEPPER` is set. Realtime push and a physical phone have not been tested.**

| Check | Command | What it proves |
|---|---|---|
| Unit tests (scoring, snake order, codes, CSV) | `npm test` | Logic matches the Swift code |
| Browser end-to-end, Supabase API mocked | `npm run test:e2e` | The app's flows work: code login, scoring, offline queue, finish, spectator page. Does **not** exercise the real database, RLS or edge functions |
| SQL tests on a scratch Postgres 16 with a local copy of the **live** schema and RLS policies (captured read-only, no data) | `docs/tests/run.sh` | Migrations 001 to 005 apply; each audited bug is shown real before 005 and gone after; functions behave (voting, ties, draft turns, scoring, triggers, audit, spectator link). Not run against the live project itself. See `docs/LIVE_SCHEMA_AUDIT.md` |

## Setup

1. Database: migrations 001 to 006 are already applied to the live project. For another project, apply them in order (`../docs/migrations/`); `../docs/tests/run.sh` proves them on a scratch database.
2. Edge functions (already deployed to the live project; for another project, deploy them and set the pepper, any long random string, never committed):

   ```bash
   supabase functions deploy redeem-code
   supabase functions deploy admin-players
   supabase secrets set CODE_PEPPER=$(openssl rand -hex 32)
   ```

   Deploy `redeem-code` with JWT verification off if the browser call is rejected (`--no-verify-jwt`), since players have no session yet.
3. Configure and run the site:

   ```bash
   cp .env.example .env.local   # fill in the project URL and publishable key
   npm install
   npm run dev
   ```

## What works

| Area | Where |
|---|---|
| Player code login | `/join`, edge function `redeem-code` |
| Captain vote (exactly 2, one ballot, counts hidden until you vote) | `components/VotePanel.tsx`, rpc `cast_captain_votes` |
| Snake draft, turn enforced in the database | `components/DraftPanel.tsx`, rpc `draft_pick` |
| Score logging, per hole autosave, offline queue, finish | `app/t/[id]/match/[mid]`, `lib/scoreQueue.ts`, rpc `set_hole_score` |
| Standings (live) and shareable PNG | `components/Standings.tsx`, `lib/shareImage.ts` |
| Public spectator link (read only, revocable) | `/watch/[token]`, rpcs `set_spectator_link`, `get_public_standings` |
| Admin: create tournament with course picker, add players and codes, print cards, codes CSV | `/admin`, `/admin/[id]` Roster tab, edge function `admin-players` |
| Admin: vote tally, tie break, override draft, start tournament, pairings | `/admin/[id]` |
| Admin: live scorecards, audited edits, recompute, results and scorecards CSV | `/admin/[id]` Scores tab |
| Admin: audit log viewer and export | `/admin/[id]` Audit tab |
| Installable app (manifest, icons, offline shell) | `public/manifest.webmanifest`, `public/sw.js` |

## Not built

- **Email / SMS code delivery.** Needs a provider (Resend, Twilio, etc.), an account, and a sender identity. Print cards and CSV work today.
- **PDF export.** CSV and the browser print dialog (Save as PDF) cover it for now.
- Real-database tests: RLS policies on the existing iOS tables, and an end-to-end run against Supabase.
- Course picker only knows the 17 KB bundled catalog (`public/courses.json`).
