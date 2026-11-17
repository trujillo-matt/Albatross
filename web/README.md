# Albatross Tournaments (web)

Next.js 14 + TypeScript + Tailwind + Supabase. Players log scores with a code; admins run the tournament.
Shares the Supabase project with the iOS app. See `../docs/TOURNAMENT_WEB_APP_PLAN.md` for the full design.

## Status

Built and type-checked (`npm run typecheck`, `npm run build`, `npm test` pass). **Not yet run against a real
Supabase project.** The database migrations and edge functions are untested, and the table/column names are inferred
from the iOS code. Expect to fix small mismatches on the first real run.

## Setup

1. Review and apply, in order, against a staging copy first: `../docs/migrations/001_*.sql`, `002_*.sql`, `003_*.sql`.
2. Deploy the edge functions and set the pepper (any long random string; never commit it):

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
| Standings (live) | `components/Standings.tsx` |
| Admin: create tournament, add players and codes, print cards | `/admin`, `/admin/[id]` Roster tab, edge function `admin-players` |
| Admin: vote tally, tie break, override draft, start tournament, pairings | `/admin/[id]` |
| Admin: live scorecards, audited edits, recompute | `/admin/[id]` Scores tab |

## Not built yet

Spectator link, CSV/PDF export, standings share image, email/SMS code delivery, audit log viewer, course picker
(course names are matched against `public/courses.json` by exact name), PWA manifest and service worker,
Playwright end-to-end tests, RLS negative tests.
