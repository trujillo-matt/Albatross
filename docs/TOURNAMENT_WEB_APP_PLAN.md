# Albatross Tournament Web App: Plan

Status: planning document. No web code has been written.
Source of truth for this plan: the Swift code in this repo (`Albatross/Models/Tournament.swift`, `Albatross/Store/TournamentStore.swift`, `Albatross/Views/Tournament/*`, `Albatross/Store/RoundStore.swift`, `Albatross/Models/Round.swift`).

## 0. Read this first: what I could and could not verify

- **Verified from code:** the data model shape, the client-side flows (create, invite, captain vote, snake draft, matchups, scorecard entry, auto-scoring), and the Supabase project URL.
- **Cannot verify:** the live Supabase schema, foreign keys, unique constraints, RLS policies, triggers, and whether `rounds.scores` is `jsonb` or `int[]`. There is no `.sql` file in the repo. Every table and column below is inferred from the `CodingKeys` and `.from("...")` calls. Step 1 of the build is to dump the real schema and diff it against this plan.
- **Where the tournaments tab lives:** there is no standalone tournaments tab. `TournamentListView()` is a section inside the Scorecards tab (`ScorecardsView.swift:178`). I treated that section plus everything it navigates to as "the tournaments tab."
- Items marked **[Inference]** are my reasoning from the code, not observed behavior. Items marked **[Recommendation]** are design opinions.

## 1. Goals

1. Players in a tournament log their own scores from a phone browser with no app install and no personal account setup.
2. Each player gets a **code** that is tied to a **player account the admin created before the tournament**.
3. The admin gets a **dashboard** with full control over roster, codes, voting, draft, pairings, scores, and results.
4. The **captain voting mechanic** and snake draft from the iOS app are reproduced.
5. The web app and the iOS app share one backend, so a tournament can mix iOS users and code-login players, and standings stay consistent.

Non-goals for v1: handicap-adjusted (net) scoring, payments, public tournament discovery, native push notifications.

## 2. What the iOS app does today (the behavior to reproduce)

Lifecycle (`TournamentStatus`): `setup` -> `draft` -> `active` -> `complete`.

| Stage | Behavior in iOS | Code |
|---|---|---|
| Create | 3-step sheet: name + number of matches (1 to 18), course + format per match, invite players. Creator becomes an accepted admin player. | `NewTournamentSheet.swift`, `TournamentStore.createTournament` |
| Invite | Admin searches users, row inserted with `invite_status = pending`. Player accepts or declines. | `TournamentStore.swift:238-293` |
| Start draft | Status -> `draft`, two teams created ("Team A", "Team B"). Needs 2+ accepted players. | `TournamentStore.startDraft` |
| Phase 1: captain vote | Every accepted player picks exactly 2 nominees. UI shows live per-player vote counts and "X of N voted." Admin taps Finalize; top 2 vote-getters become captains of Team A and Team B. | `TournamentDraftView.captainVotePhase`, `finalizeCaptains` |
| Phase 2: snake draft | Captains alternate picks in order A, B, B, A, A, B, B, A, repeating. Admin can override any assignment. | `snakeIsTeamATurn`, `draftPick`, `overridePickRow` |
| Start tournament | Creates one `tournament_matchups` row per match, using the per-round format from `tournament_courses`. Status -> `active`. | `TournamentStore.startTournament` |
| Pairings | Admin or a captain picks 1 or 2 players per side (sides must be equal size). Matchup -> `active`. | `TournamentMatchupView.pairingsEditor` |
| Score entry | Each paired player gets their own `Round` tied to the matchup, enters 18 hole scores (range 1 to 20), taps finish. Link row written to `tournament_matchup_rounds`. | `TournamentScorecardWrapperView`, `ScoreInputView` |
| Auto-result | When completed rounds >= paired players, the client computes points and writes the matchup result. | `TournamentScorecardWrapperView.handleFinish`, `calculateAndSaveMatchupResult` |
| Standings | Sum of matchup points per team; realtime subscription; share-card image. Tournament flips to `complete` when a team reaches `pointsToWin`. | `TournamentStandingsView` |

Scoring rules (`Tournament.swift:223-282`), each matchup is worth exactly 1 point:

- **Match play:** per hole, the lower of each side's best scores wins the hole. Most holes won takes the point, halved match = 0.5 each.
- **Best ball and scramble:** sum of per-hole minimum across the side's players. Lower total takes the point.
- **Stroke play:** lowest single player total on each side takes the point.
- All scoring is gross. No handicap strokes.

## 3. Problems in the existing implementation (fix in the web app, do not copy)

These matter because the web app will sit on the same data. Each is verified by reading the cited code, except where marked.

1. **`pointsToWin` is wrong for small tournaments.** The setup sheet footer says points to win = `matches / 2 + 0.5` (`NewTournamentSheet.swift:89`), but `createTournament` is called without that value (`NewTournamentSheet.swift:354-360`), so the default `9.5` is used (`TournamentStore.swift:180`). Each match is worth at most 1 point, so a 3-match tournament (the default) can never reach 9.5 and the auto-complete check (`TournamentStore.swift:566`) never fires. Web app: compute `total / 2 + 0.5` server-side (3 matches -> 2.0, 4 -> 2.5) and let the admin override it.
2. **Captain tie-break is nondeterministic.** `finalizeCaptains` builds a `[UUID: Int]` dictionary and sorts by count (`TournamentStore.swift:337-339`). Ties are broken by dictionary order, which Swift randomizes per process. Web app: explicit tie detection, admin resolves.
3. **Team A and Team B identity is positional and unordered.** (**iOS: fixed.** `loadTeams` now orders by name with an id tie-break, so `teams[0]` is always Team A. **Web: specified, not yet built.** The web app must never rely on row order: add a `side` column (`A` or `B`, unique per tournament) via `docs/migrations/001_tournament_team_side.sql` and read teams by `side`. After that migration is applied, the iOS code should switch from name order to `side` too.) Original issue: no `order` clause (`TournamentStore.swift:135-142`) with `teams[0]` and `teams[1]` used at `:346-353` and `:577-578`, so Team A could flip between loads.
4. **Captains are not placed on their own team.** `finalizeCaptains` sets `captain_user_id` only (`:345-353`). The draft pool is "accepted and `teamID == nil`" (`TournamentDraftView.swift:40`). **[Inference]** the captains themselves therefore appear in the undrafted pool. Web app: finalizing captains also assigns each captain to their team.
5. **Voting rules are enforced only in the client.** "Already voted" is a client check (`TournamentDraftView.swift:79-82`). Votes are inserted in a loop, not atomically (`:316-324`). Self-nomination is allowed. **[Cannot verify]** whether the DB has a unique constraint. Web app: one atomic RPC, unique constraint on `(tournament_id, voter, nominee)`, exactly 2 distinct nominees, decide on self-votes (see open questions).
6. **Draft turn order is client-enforced.** `draftPick` checks that the caller is a captain, not that it is their turn (`TournamentStore.swift:358-364`). Web app: the pick RPC computes whose turn it is from the pick count and rejects out-of-turn picks.
7. **Tournament rounds use fallback pars.** The wrapper creates `Round(courseName:..., tournamentMatchupID:...)` with no course metadata (`TournamentScorecardWrapperView.swift:53-56`), so `effectivePars` falls back to a generic layout (`Round.swift:40-43`). `tournament_courses` stores only a free-text `course_name`. Web app: link `tournament_courses` to a real course (id + par/handicap/yardage per hole) so scorecards show real pars.
8. **Scramble requires every teammate to enter a card.** Completion needs `completedRounds.count >= allPlayerIDs.count` (`TournamentScorecardWrapperView.swift:84`). In a scramble the team plays one ball, so two partners would enter identical cards. Web app: one team card with a designated scorer.
9. **Result computation is client-side and racy.** Whichever device finishes last computes and writes the result. Two simultaneous finishers can both write. Web app: compute in a Postgres function triggered by round completion, idempotent.
10. **Whole-array score writes.** `RoundStore.syncToCloud` upserts the full `scores` array (`RoundStore.swift:178-189`). Two writers to one card would overwrite each other. Web app: per-hole RPC.
11. **Live vote counts are visible to all voters** (`TournamentDraftView.swift:179-184`), which invites bandwagon voting. This may be intended. See open questions.

### Fix status for section 3

iOS changes are in the Swift code (not compiled here). Database changes are in `docs/migrations/` and are **not applied or tested**. The web app does not exist yet; its column reads the migration column.

| # | iOS | Database / web |
|---|---|---|
| 1 | Fixed: `defaultPointsToWin` used on create; tournament also completes when all matches are played | Migration 002 corrects existing rows still at 9.5 |
| 2 | Fixed: deterministic ranking, tie raises `captainTie`, commissioner tie-break sheet | `finalize_captains` in 002 |
| 3 | Fixed: teams ordered by name | `side` column in 001 |
| 4 | Fixed: captains placed on their team, excluded from pick count | `finalize_captains` in 002 |
| 5 | Fixed: single atomic insert, exactly 2 distinct, one ballot | Unique index + `cast_captain_votes` in 002 |
| 6 | Fixed: pick rejected if not that captain's turn or player unavailable (client check on fresh data, still raceable) | `draft_pick` in 002 (race-free) |
| 7 | Fixed when the course name matches the catalog; otherwise fallback pars remain | `course_id` column in 002; picker UI is future work |
| 8 | Fixed: scramble needs one card per team, with a hint in the UI | `scorer_user_id` column in 002 |
| 9 | Not changed on iOS (writes are idempotent, race is narrow) | `compute_matchup_result` + triggers in 002 |
| 10 | Not changed: iOS still writes the whole array | `set_hole_score` in 002, for the web app |
| 11 | Fixed: counts hidden from voters until they vote (commissioner always sees) | Make this a setting in the web app |

## 4. Architecture

**[Recommendation]** Reuse the existing Supabase project. Do not build a second backend.

- **Database, auth, realtime:** existing Supabase project (the iOS client talks to `rtcyetcyhdrajvcstvlj.supabase.co`). Same tables, plus a migration for additions in section 5.
- **Server logic:** Supabase Edge Functions (code redemption, code generation, bulk import) and Postgres functions (voting, draft pick, hole score, result calculation). Rules live in the database so iOS and web cannot disagree.
- **Web client:** Next.js (App Router) + TypeScript + Tailwind + `supabase-js`, deployed to Vercel. Delivered as an installable **PWA** so phones can add it to the home screen. Vite + React SPA is an acceptable simpler alternative since nothing here needs SSR beyond the public spectator page.
- **Realtime:** Supabase Realtime (already used by iOS in `subscribeToDraftRoom` and `subscribeToStandings`). Same channel filters.
- **Offline:** service worker + IndexedDB queue for score writes. Golf courses have poor signal. This is not optional for a score-logging app.

Two audiences, two auth paths into the same database:

| Audience | Sign-in | Result |
|---|---|---|
| Admin | Existing email + password (same accounts as iOS) | Normal Supabase session |
| Player | Tournament code | Supabase session for a pre-created player account |

## 5. The player account and code system (the core requirement)

### 5.1 Design choice

**[Recommendation] Option A: real auth users flagged as managed.** For each player the admin pre-creates, the system creates a real `auth.users` row plus a `profiles` row with `is_managed = true`. The code redeems into a normal Supabase session for that user.

Why: every existing table keys on `user_id` (`tournament_players.user_id`, `rounds.user_id`, `tournament_matchup_rounds.user_id`, captain votes, team captains). Option A means all of that, plus the iOS scoring and standings, works unchanged. A managed player and an iOS player can be on opposite sides of the same match.

Option B (custom JWT with a `player_id` claim and separate tables) keeps `auth.users` clean but forces a parallel set of tables or a rewrite of RLS and the iOS client. Rejected for v1.

### 5.2 Tables added

```
profiles
  + is_managed        boolean not null default false
  + managed_by        uuid references profiles(id)      -- the admin who created it
  + claimed_at        timestamptz                       -- set if the player later attaches a real login

player_access_codes
  id                  uuid pk
  tournament_id       uuid not null references tournaments(id) on delete cascade
  user_id             uuid not null references profiles(id)
  code_hash           text not null                     -- never store the plain code
  code_hint           text                              -- last 2 characters, for admin display only
  status              text not null default 'active'    -- active | revoked | expired
  expires_at          timestamptz                       -- default: tournament end + 2 days
  failed_attempts     int not null default 0
  last_used_at        timestamptz
  created_by          uuid not null references profiles(id)
  created_at          timestamptz not null default now()
  revoked_at          timestamptz
  unique (tournament_id, user_id) where status = 'active'

code_redeem_attempts                                    -- rate limiting + forensics
  id, ip_hash, code_prefix_tried, success bool, created_at

tournament_audit_log
  id, tournament_id, actor_user_id, action text, target_type, target_id, before jsonb, after jsonb, reason text, created_at
```

Also add: `tournament_teams.side` ('A' | 'B'), `tournaments.captain_vote_status` ('closed' | 'open' | 'tied' | 'final'), `tournament_courses.course_id` + `tee`, `tournament_matchups.scorer_user_id` (for scramble), `tournaments.public_token` (spectator link).

### 5.3 Code format and handling

- **8 characters, Crockford base32** (no 0/O, 1/I/L confusion), shown as `K7M2-9QXH`. About 40 bits.
- Stored as a salted hash (or HMAC with a server-side pepper). The plain code is shown to the admin **once** at generation. If lost, the admin regenerates (old one is revoked). **[Recommendation]** hash-only is the safer default. The alternative is storing the code encrypted so the admin can re-view it, which is more convenient and a bigger breach surface.
- Codes are **scoped to a tournament and a single player**. Redeeming a code never exposes other tournaments for that account.
- **Rate limiting** on redemption: per IP and per code prefix, lockout after N failures, all in an edge function. 40 bits is only adequate because of this.
- Admin actions: generate, regenerate, revoke, extend expiry, force sign-out, see last used.

### 5.4 Redemption flow

1. Player opens the site, types the code.
2. Edge function `redeem-code` (service role): normalizes input (uppercase, strip dashes, map confusable characters), checks rate limit, looks up the hash, checks `status = active` and `expires_at`, and checks the tournament is not `complete`.
3. On success it mints a session for that player's `auth.users` row. **Mechanism to confirm in the spike:** server-side sign-in using a server-held credential for the managed user, or `auth.admin.generateLink` then verify. Both are supported patterns in Supabase Auth but I have not tested either against this project. The managed user's password is random, never shown, and rotated on each redemption.
4. Function returns the session (access + refresh token). Client stores it with `supabase-js`. Player lands on their tournament home.
5. `last_used_at` updated, audit row written.
6. Optional (setting): single active device per code, so a shared or leaked code is noticed.

### 5.5 RLS posture

**[Cannot verify current RLS.]** Before this ships, audit every policy on the tournament tables and `rounds`. Required behavior:

- A player can read tournaments they are in, and write only their own votes, their own round, and (if designated scorer) the team card for their matchup.
- Only tournament admins can change roster, codes, status, pairings (captains may set pairings for their side), and edit others' scores.
- Managed players cannot read other tournaments or any profile data outside their tournaments.
- The Supabase key committed in `SupabaseClient.swift` is a publishable key, which is designed to be public, but that is only safe if RLS is correct. Adding a public web front end increases the traffic that will probe it.

### 5.6 Later: claiming an account

A managed player who later installs the iOS app can attach an email (`claimed_at` set), keeping their tournament history. Not v1.

## 6. Admin dashboard

Access: admin signs in with email and password. A user is an admin of a tournament if they are `creator_user_id` or `tournament_players.is_admin = true`. Note iOS only checks `creator_user_id` in most places (`TournamentDetailView.swift:18-20`, `TournamentDraftView.swift:21`); the web app should honor `is_admin` too and iOS should follow.

### 6.1 Screens

1. **Tournaments list:** status badges, create, duplicate (clone a past event's courses and formats), archive.
2. **Overview:** live status, next action prompt ("12 of 16 players have voted"), quick links, standings snapshot, activity feed.
3. **Setup:** name, number of matches, per-match course (picked from course catalog) and format, points to win (default computed, editable), vote settings, scoring options.
4. **Roster and codes:**
   - Add managed players one at a time or by CSV paste (name, optional email/phone, optional handicap).
   - Link existing iOS users by username search (same as the current invite flow).
   - Per-row: code status, last seen, regenerate, revoke.
   - **Print code cards** (PDF, 4 per page, QR deep-linking to `/join?code=...`), copy-all, and optional email/SMS send (phase 4).
   - Roster shows who has signed in, so the admin knows who is missing before the first tee time.
5. **Captain vote control:**
   - Open and close voting. Live tally and turnout visible to the admin always.
   - Detects ties at the captain cutoff and presents a resolve UI (pick winners, or open a runoff of only the tied nominees).
   - Finalize captains, which also places captains on their teams.
   - Reset votes (audited).
6. **Draft board:** live two-column board, whose turn it is, pick history, admin override and **undo last pick**, optional pick timer with auto-pick, "start tournament" when the pool is empty.
7. **Matchups:** per match, set or edit pairings, set designated scorer for scramble, reopen a completed match.
8. **Score oversight:**
   - Live grid of every active round: hole progress, running total, last update time, stale-card flags.
   - Open any scorecard, edit any hole with a required reason (written to the audit log), lock or unlock a card, mark withdrawal or DQ.
   - Manually override a matchup result, with reason, and a "recompute" button.
9. **Standings and sharing:** live standings, per-match results, PNG share card (port of `StandingsShareCard`), public read-only spectator link with a revocable token.
10. **Audit log and export:** filterable log, CSV and PDF export of results and all scorecards.
11. **Danger zone:** delete tournament, with typed-name confirmation.

### 6.2 Admin guardrails

- Every admin mutation is an RPC that checks admin rights server-side and writes the audit log.
- Status changes are forward-only by default; "step back a stage" is a separate confirmed action that warns about downstream data.

## 7. Player experience (phone-first)

Routes:

| Route | Purpose |
|---|---|
| `/join` | Enter code, or arrive pre-filled from the QR. Confirms "You are Jane D., Spring Classic" before continuing. |
| `/t/:id` | Tournament home. Shows stage, my team, my next match, standings strip. Content depends on `status`. |
| `/t/:id/vote` | Captain vote. |
| `/t/:id/draft` | Draft room (everyone watches, captains pick). |
| `/t/:id/matches` | List of matches with status. |
| `/t/:id/matches/:mid` | Pairings, my scorecard, live match status. |
| `/t/:id/standings` | Standings and per-match results. |

### 7.1 Captain voting (reproduced from iOS)

- Each accepted player selects **exactly 2 nominees** and submits once. After submitting, the screen is read-only with "Your vote has been submitted."
- Show turnout: "N of M players voted."
- Live per-player counts: **setting**, default matches iOS (visible), admin can switch to "hidden until closed."
- Rules enforced in a single RPC `cast_captain_votes(tournament_id, nominee_ids[2])`: caller is an accepted player, voting is open, nominees are 2 distinct accepted players, caller has not voted. Self-nomination: setting (default allowed, matching iOS).
- Admin closes voting. If the 2nd and 3rd place counts are tied, status becomes `tied` and the admin resolves. Otherwise top 2 become captains automatically on finalize.
- Realtime: subscribe to `tournament_captain_votes` inserts, same as iOS.

### 7.2 Snake draft (reproduced)

- Pick order A, B, B, A, A, B, B, A, repeating (`pick_number % 4 in {0, 3}` is Team A).
- Everyone sees both rosters and the on-the-clock indicator in realtime. The on-clock captain sees the pool with an add button. Others see "Team X is on the clock."
- Server-side `draft_pick(player_id)` verifies caller is the on-clock captain.

### 7.3 Score logging (the main feature)

Flow for a paired player:

1. Open `/t/:id/matches/:mid`. See course, format, opponents, tee.
2. Tap **Start scorecard**. Server creates (or returns) a `rounds` row with `matchup_id`, course metadata copied from the linked course (pars, handicaps, yardages, rating, slope), and a `tournament_matchup_rounds` link. Idempotent, so a refresh never creates a second card.
3. **Hole-by-hole entry.** One big hole at a time: hole number, par, yardage, large number pad (1 to 20, same range as `ScoreInputView`), plus a full 18-hole grid view for quick jumps and corrections. Running total and score-to-par shown.
4. **Autosave per hole** through RPC `set_hole_score(round_id, hole, strokes)`, which updates one array element atomically. Offline, writes queue in IndexedDB with a visible "N unsynced" badge and replay in order on reconnect.
5. **Validation:** integer 1 to 20, confirm prompt if the score is more than 5 over par (typo guard), cannot skip ahead past an empty hole without a flag.
6. **Live match status** under the card: for match play "Team A 2 UP thru 9," for best ball running totals. Computed from the same data as the final result.
7. **Finish:** player confirms the card. Round status -> `completed`, and the card locks. Only an admin can unlock.
8. **Server computes the result** when every paired round is complete (section 7.4). The player sees the final result and updated standings.

Format-specific behavior:

| Format | Cards entered | Notes |
|---|---|---|
| Best ball | One per player, own ball | Team hole score = lowest of the side. Matches iOS. |
| Match play | One per player | Shows holes up/down live. |
| Stroke play | One per player | Side total = lowest single player total, matching iOS. |
| Scramble | **One per team**, by designated scorer | Fixes problem 8. Either teammate can be scorer; admin can reassign. |

Edge cases to handle explicitly: player on an unstable connection (offline queue), two devices open on the same card (last write wins per hole, with a timestamp shown), player picks up (admin marks the hole or card), match decided early in match play (v1 still plays all 18 and keeps the iOS behavior of one point per match), card finished but opponent is not (match stays `active`).

### 7.4 Result calculation

Port the three scoring functions (`calculateMatchPlayPoints`, `calculateBestBallPoints`, `calculateStrokePlayPoints`) to a Postgres function `compute_matchup_result(matchup_id)`, called by a trigger when a round becomes `completed`. It is idempotent (recomputes from current data), writes `result`, `points_team_a`, `points_team_b`, `status = complete`, then checks `pointsToWin` and sets the tournament `complete`. Admin recompute button calls the same function.

**Required test:** golden-file tests that feed identical inputs to the Swift functions and the SQL function and assert identical output, including ties and incomplete holes. This is the only way to be sure iOS and web agree.

## 8. Data model summary

Existing tables (inferred, to be confirmed against the live DB): `tournaments`, `tournament_courses`, `tournament_players`, `tournament_teams`, `tournament_captain_votes`, `tournament_matchups`, `tournament_matchup_rounds`, `rounds`, `profiles`.

New or changed: see 5.2. New RPCs:

| RPC | Caller | Purpose |
|---|---|---|
| `admin_create_managed_player` | admin | Creates auth user, profile, tournament_players row, access code. |
| `admin_regenerate_code`, `admin_revoke_code` | admin | Code lifecycle. |
| `open_captain_vote`, `close_captain_vote`, `finalize_captains` | admin | Vote lifecycle, tie handling, assigns captains to teams. |
| `cast_captain_votes` | player | Atomic vote. |
| `draft_pick`, `draft_undo` | captain, admin | Turn-enforced pick. |
| `start_tournament` | admin | Creates matchups, computes points to win. |
| `set_pairings` | admin, captain | Pairings with equal-size check. |
| `start_round`, `set_hole_score`, `finish_round` | player (own card), admin (any) | Score entry. |
| `compute_matchup_result` | trigger, admin | Scoring. |
| `admin_edit_score`, `admin_override_result` | admin | Audited overrides. |

## 9. Security and abuse considerations

- Hash codes; rate limit and lock out on failures; log every attempt.
- Codes scoped to one tournament and expire automatically.
- Session lifetime for managed players: tournament duration, no refresh after revoke (force sign-out by invalidating refresh tokens).
- Service role key only in edge functions, never in the browser.
- Admin override actions require a reason and are immutable in the audit log.
- Spectator link is read-only, token-based, revocable, and exposes only names and scores.
- Privacy: managed player records can contain contact info the admin typed in. Restrict it to admins, and add a delete-after-event option.
- RLS audit and a negative test suite (player A cannot read or write player B's card, a managed player cannot see another tournament) before launch.

## 10. Testing strategy

- **Unit:** scoring functions (golden parity with Swift), snake order, tie detection, code normalization.
- **Database:** pgTAP or SQL tests for each RPC, including permission-denied cases.
- **RLS negative tests:** scripted attempts to read and write across players and tournaments.
- **E2E (Playwright):** admin creates tournament, adds 8 managed players, prints codes; 8 browser contexts redeem codes, vote, draft, play, finish; assert standings. Includes an offline-then-reconnect scoring test.
- **Cross-client:** one iOS player in a tournament with web players, same results both sides.
- **Load:** roughly 100 concurrent scorers hitting `set_hole_score` plus realtime fan-out. **[Inference]** the expected load is small, but verify Realtime connection limits on the current Supabase plan.

## 11. Delivery phases

Time estimates are **[Inference]** and assume one developer who knows the stack.

| Phase | Scope | Rough effort |
|---|---|---|
| 0. Discovery | Dump live schema and RLS, confirm `rounds.scores` type, confirm session-minting approach in a throwaway spike, decide open questions | 2 to 3 days |
| 1. Backend foundation | Migration (section 5.2), RPCs, scoring function with parity tests, RLS rewrite, audit log | 1.5 to 2 weeks |
| 2. Code login + admin roster | `/join`, `redeem-code`, admin auth, tournament CRUD, managed players, code cards | 1.5 to 2 weeks |
| 3. Player score logging | Match page, scorecard UI, autosave, offline queue, finish and result | 2 weeks |
| 4. Voting and draft | Vote UI, admin vote control, tie flow, draft room, captain placement | 1.5 weeks |
| 5. Admin oversight | Live score grid, edit and lock, overrides, standings, share image, spectator link, export | 1.5 to 2 weeks |
| 6. Hardening | RLS negative tests, E2E suite, load check, PWA polish, accessibility pass | 1 week |

**Smallest useful release (MVP):** phases 0 to 3 plus admin standings. That gets code-based players logging scores and the admin seeing results. Voting and draft can be run in the iOS app until phase 4 lands, since both clients share the data.

## 12. Open questions (answers change the build)

1. **Mixed field or code-only?** Will iOS-app users and code players play in the same tournament? Plan assumes yes (Option A). If code-only, a simpler design is possible.
2. **Can a player vote for themselves?** iOS allows it.
3. **Live vote counts visible during voting?** iOS shows them. Default kept, with a hidden option.
4. **Ties at the captain cutoff:** admin picks, runoff, or coin flip?
5. **Scramble:** confirm one card per team with a designated scorer.
6. **Handicaps / net scoring:** gross only for v1, as in iOS?
7. **Points to win:** `matches / 2 + 0.5`, as the setup sheet footer states. Implemented in iOS; confirm.
8. **Code delivery:** printed cards and QR only, or also email and SMS (adds a provider and cost)?
9. **Course data:** `courses.json` currently ships inside the iOS bundle (17 KB). Move it into a database table so both clients share it?
10. **Spectators:** do non-players need a public live-standings link?
11. **Who is an admin:** just the creator, or `is_admin` co-admins too?
12. **Expected size:** number of players per event, to size Realtime and confirm plan limits.

## 13. Immediate next steps

1. Export the live schema, RLS policies, triggers, and constraints from Supabase and diff against this plan.
2. Run the session-minting spike (section 5.4 step 3) to prove a code can become a working session.
3. Get answers to the open questions above.
4. Scaffold the repo (`web/` folder in this repo or a sibling repo) and the migration, then start phase 1.
