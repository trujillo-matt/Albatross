// End-to-end tests in a real browser against the production build, with the Supabase API mocked
// (so they prove the web app's behavior, NOT the real database, RLS, migrations or edge functions).
// Run: npm run test:e2e   (builds with a mock Supabase URL, starts the server, runs, stops it)
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const { chromium } = require("playwright");

const BASE = process.env.E2E_BASE ?? "http://localhost:3100";
const API = "https://mock.supabase.test";
const TID = "11111111-1111-4111-8111-111111111111";
const MID = "22222222-2222-4222-8222-222222222222";
const ME = "33333333-3333-4333-8333-333333333333";
const OPP = "44444444-4444-4444-8444-444444444444";
const TA = "55555555-5555-4555-8555-555555555555";
const TB = "66666666-6666-4666-8666-666666666666";
const P3 = "77777777-7777-4777-8777-777777777777";   // Team A, plays with ME
const P4 = "88888888-8888-4888-8888-888888888888";   // Team B, plays with OPP
const GROUP_OWNERS = [ME, P3, OPP, P4];               // card order: side A first

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const jwt = () => `${b64({ alg: "HS256", typ: "JWT" })}.${b64({ sub: ME, role: "authenticated", aud: "authenticated", email: "p@x.test", exp: Math.floor(Date.now() / 1000) + 3600 })}.sig`;
const user = { id: ME, aud: "authenticated", role: "authenticated", email: "p@x.test", app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() };

const cors = { "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" };
const reply = (route, status, body) =>
  route.fulfill({ status, headers: { ...cors, "content-type": "application/json" }, body: body === undefined ? "" : JSON.stringify(body) });

const table = {
  tournaments: { id: TID, name: "Test Cup", creator_user_id: OPP, status: "active", match_type: "best_ball", total_matches: 1, points_to_win: 1.5 },
  tournament_courses: [{ id: "c1", tournament_id: TID, course_name: "Pebble Beach Golf Links", round_number: 1, match_type: "best_ball" }],
  tournament_players: [
    { id: "p1", tournament_id: TID, user_id: ME, team_id: TA, invite_status: "accepted", is_admin: false },
    { id: "p2", tournament_id: TID, user_id: OPP, team_id: TB, invite_status: "accepted", is_admin: true },
  ],
  tournament_teams: [
    { id: TA, tournament_id: TID, name: "Team A", captain_user_id: ME, side: "A" },
    { id: TB, tournament_id: TID, name: "Team B", captain_user_id: OPP, side: "B" },
  ],
  tournament_matchups: [{ id: MID, tournament_id: TID, matchup_number: 1, team_a_id: TA, team_b_id: TB, team_a_player_ids: [ME], team_b_player_ids: [OPP], match_type: "best_ball", status: "active", result: null, points_team_a: 0, points_team_b: 0 }],
  tournament_captain_votes: [],
  profiles: [{ id: ME, display_name: "Pat Player" }, { id: OPP, display_name: "Olive Opp" }],
};

let browser;
before(async () => { browser = await chromium.launch(); });
after(async () => { await browser.close(); });

/** Installs the mock API on a page. `state` lets a test flip the network and inspect calls. */
async function mockApi(page, state) {
  await page.route(`${API}/**`, async (route) => {
    const req = route.request();
    const url = new URL(req.url());
    if (req.method() === "OPTIONS") return route.fulfill({ status: 204, headers: cors });
    const p = url.pathname;

    if (p === "/functions/v1/redeem-code") {
      state.redeemBody = req.postDataJSON();
      if (state.redeem?.status) return reply(route, state.redeem.status, state.redeem.body);
      return reply(route, 200, { access_token: jwt(), refresh_token: "r", tournament_id: TID });
    }
    if (p === "/auth/v1/user") return reply(route, 200, user);
    if (p.startsWith("/rest/v1/rpc/")) {
      const name = p.split("/").pop();
      state.rpc.push({ name, args: req.postDataJSON() });
      if (name === "set_hole_score" && state.offline) return route.abort("internetdisconnected");
      if (name === "get_public_standings") return reply(route, 200, state.publicData ?? null);
      // Group scoring (migration 009), just enough of the database's behavior for the screens
      if (name === "set_scorer") { state.scorer = req.postDataJSON().p_scorer; return reply(route, 200, null); }
      if (name === "start_group_scoring") {
        state.cards = GROUP_OWNERS.map((uid, i) => ({
          id: "card" + (i + 1), user_id: uid, course_name: "Pebble Beach Golf Links", matchup_id: MID, status: "in_progress",
          course_pars: null, course_yardages: null,
          scores: Array.from({ length: 18 }, (_, h) => (h === 0 ? null : i < 2 ? 4 : 5)),   // everything but hole 1 is already in
        }));
        return reply(route, 200, state.cards.map((c) => ({ out_round: c.id, out_owner: c.user_id, out_side: c.user_id === ME || c.user_id === P3 ? "A" : "B" })));
      }
      if (name === "finish_group_scoring") { state.cards = state.cards.map((c) => ({ ...c, status: "completed" })); return reply(route, 200, null); }
      return reply(route, 200, null);
    }
    if (p.startsWith("/rest/v1/")) {
      const name = p.split("/").pop();
      if (req.method() === "GET") {
        if (name === "rounds") return reply(route, 200, state.cards ?? (state.round ? [state.round] : []));
        if (name === "tournament_matchup_rounds") return reply(route, 200, []);
        let data = table[name] ?? [];
        if (state.group) {   // a 2 v 2 match whose scorer can change during the test
          if (name === "tournament_matchups") data = [{ ...table.tournament_matchups[0], team_a_player_ids: [ME, P3], team_b_player_ids: [OPP, P4], scorer_user_id: state.scorer ?? null }];
          if (name === "tournament_players") data = [...table.tournament_players, { id: "p3", tournament_id: TID, user_id: P3, team_id: TA, invite_status: "accepted", is_admin: false }, { id: "p4", tournament_id: TID, user_id: P4, team_id: TB, invite_status: "accepted", is_admin: false }];
          if (name === "profiles") data = [...table.profiles, { id: P3, display_name: "Quinn Third" }, { id: P4, display_name: "Riley Fourth" }];
        }
        const single = (req.headers().accept ?? "").includes("pgrst.object");
        return reply(route, 200, single && Array.isArray(data) ? data[0] : data);
      }
      state.writes.push({ method: req.method(), name, body: req.postDataJSON?.() });
      if (name === "rounds" && req.method() === "POST") state.round = { ...req.postDataJSON(), status: "in_progress" };
      if (name === "rounds" && req.method() === "PATCH") state.round = { ...state.round, ...req.postDataJSON() };
      return reply(route, 201, undefined);
    }
    return reply(route, 404, { error: "unmocked " + p });
  });
}
const newState = () => ({ rpc: [], writes: [], offline: false, round: null });

test("join: button needs 8 characters and the code is normalized before sending", async () => {
  const page = await browser.newPage(); const s = newState();
  await mockApi(page, s); s.redeem = { status: 401, body: { error: "That code is not valid." } };
  await page.goto(`${BASE}/join`);
  const go = page.getByRole("button", { name: "Continue" });
  await page.getByPlaceholder("XXXX-XXXX").fill("k7m2-9q");
  assert.equal(await go.isDisabled(), true);
  await page.getByPlaceholder("XXXX-XXXX").fill("k7m2-9qxh");
  assert.equal(await go.isDisabled(), false);
  await go.click();
  await page.getByText("That code is not valid.").waitFor();
  assert.equal(s.redeemBody.code, "K7M29QXH");
  await page.close();
});

test("join: rate limit message is shown", async () => {
  const page = await browser.newPage(); const s = newState();
  await mockApi(page, s); s.redeem = { status: 429, body: { error: "Too many attempts. Try again in a few minutes." } };
  await page.goto(`${BASE}/join`);
  await page.getByPlaceholder("XXXX-XXXX").fill("ABCD2345");
  await page.getByRole("button", { name: "Continue" }).click();
  await page.getByText("Too many attempts").waitFor();
  await page.close();
});

test("player flow: code login, start card, score holes, survive going offline, finish", async () => {
  const page = await browser.newPage(); const s = newState();
  await mockApi(page, s);
  await page.goto(`${BASE}/join`);
  await page.getByPlaceholder("XXXX-XXXX").fill("ABCD-2345");
  await page.getByRole("button", { name: "Continue" }).click();

  await page.waitForURL(`**/t/${TID}`);
  await page.getByRole("heading", { name: "Test Cup" }).waitFor();
  await page.getByText("Pat Player").first().waitFor();
  await page.getByText("Match 1").first().click();

  await page.waitForURL(`**/match/${MID}`);
  await page.getByRole("button", { name: "Start scorecard" }).click();

  // Real pars and yardage from the course catalog, not the generic fallback.
  await page.getByText("Par 4 · 381 yds").waitFor();
  assert.equal(s.round.course_name, "Pebble Beach Golf Links");
  assert.equal(s.round.course_pars.length, 18);
  assert.ok(s.writes.some((w) => w.name === "tournament_matchup_rounds"), "round linked to the matchup at start");

  const tap = async (n) => { await page.getByRole("button", { name: String(n), exact: true }).first().click(); await page.waitForTimeout(250); };
  await tap(4);
  await page.getByText("Synced", { exact: true }).waitFor();
  assert.deepEqual(s.rpc.filter((r) => r.name === "set_hole_score")[0].args, { p_round: s.round.id, p_hole: 1, p_strokes: 4 });

  // Lose signal: the score still shows and is queued.
  s.offline = true;
  await tap(5);
  await page.getByText("1 unsynced").waitFor();
  // Regain signal.
  s.offline = false;
  await page.evaluate(() => window.dispatchEvent(new Event("online")));
  await page.getByText("Synced", { exact: true }).waitFor();
  assert.ok(s.rpc.some((r) => r.name === "set_hole_score" && r.args.p_hole === 2 && r.args.p_strokes === 5), "queued score replayed");

  // Fill the rest of the card (the page was seeded from the local state, so reflect saved scores).
  for (let h = 3; h <= 18; h++) await tap(4);
  await page.getByText("18/18 holes").waitFor();
  await page.getByRole("button", { name: "Finish and submit scorecard" }).click();
  await page.getByText("Scorecard submitted").waitFor();
  assert.ok(s.writes.some((w) => w.method === "PATCH" && w.name === "rounds" && w.body.status === "completed"));
  await page.close();
});

test("spectator page renders live standings from the public token, and shows a dead link message", async () => {
  const page = await browser.newPage(); const s = newState();
  await mockApi(page, s);
  s.publicData = {
    name: "Spectator Cup", status: "active", points_to_win: 1.5,
    teams: [{ id: TA, name: "Team A", side: "A", players: ["Pat"] }, { id: TB, name: "Team B", side: "B", players: ["Olive"] }],
    matchups: [{ number: 1, type: "best_ball", status: "complete", team_a_id: TA, team_b_id: TB, points_a: 1, points_b: 0 }],
  };
  await page.goto(`${BASE}/watch/${"a".repeat(64)}`);
  await page.getByRole("heading", { name: "Spectator Cup" }).waitFor();
  await page.getByText("1.0 to 0.0").first().waitFor();
  await page.getByText("Team A vs Team B").waitFor();

  s.publicData = null;
  await page.goto(`${BASE}/watch/${"b".repeat(64)}`);
  await page.getByText("This link is not active").waitFor();
  await page.close();
});

async function signInAndOpenMatch(page) {
  await page.goto(`${BASE}/join`);
  await page.getByPlaceholder("XXXX-XXXX").fill("ABCD-2345");
  await page.getByRole("button", { name: "Continue" }).click();
  await page.waitForURL(`**/t/${TID}`);
  await page.getByText("Match 1").first().click();
  await page.waitForURL(`**/match/${MID}`);
}

test("group scoring: one player volunteers, enters everyone's strokes, and submits for the group", async () => {
  const page = await browser.newPage(); const s = newState(); s.group = true;
  await mockApi(page, s);
  await signInAndOpenMatch(page);

  // Before anyone volunteers, the individual flow is still on offer next to the group offer.
  await page.getByRole("button", { name: "Start scorecard" }).waitFor();
  await page.getByRole("button", { name: "I'll keep score for the group" }).click();
  await page.getByText("You are keeping score for the group").waitFor();
  assert.deepEqual(s.rpc.find((r) => r.name === "set_scorer").args, { p_matchup: MID, p_scorer: ME });
  assert.equal(await page.getByRole("button", { name: "Start scorecard" }).count(), 0, "the one-card-per-player flow is hidden once a scorer is set");

  await page.getByRole("button", { name: "Start the group scorecards" }).click();
  await page.getByRole("heading", { name: /Hole 1/ }).waitFor();   // opens on the first empty hole
  const start = s.rpc.find((r) => r.name === "start_group_scoring").args;
  assert.equal(start.p_matchup, MID);
  assert.equal(start.p_course.course_name, "Pebble Beach Golf Links");
  assert.equal(await page.getByRole("button", { name: /Finish and submit the group/ }).isDisabled(), true, "cannot submit with a hole missing");

  if (process.env.E2E_SHOT_DIR) await page.screenshot({ path: `${process.env.E2E_SHOT_DIR}/group-scorer.png`, fullPage: true });
  // One hole for four players: each tap saves that player's card, then moves to the next player.
  for (const n of [4, 5, 4, 6]) {
    await page.getByRole("button", { name: String(n), exact: true }).first().click();
    await page.waitForTimeout(300);
  }
  const saved = s.rpc.filter((r) => r.name === "set_hole_score").map((r) => r.args);
  assert.deepEqual(saved, [
    { p_round: "card1", p_hole: 1, p_strokes: 4 }, { p_round: "card2", p_hole: 1, p_strokes: 5 },
    { p_round: "card3", p_hole: 1, p_strokes: 4 }, { p_round: "card4", p_hole: 1, p_strokes: 6 },
  ], "each tap wrote the right player's card, in order");

  const finish = page.getByRole("button", { name: /Finish and submit the group/ });
  await page.waitForFunction(() => !document.querySelector("button.btn.w-full:disabled"));
  await finish.click();
  await page.getByText("Group scorecards submitted").waitFor();
  assert.ok(s.rpc.some((r) => r.name === "finish_group_scoring" && r.args.p_matchup === MID));
  await page.close();
});

test("group scoring: the other players see who is scoring and a read-only view", async () => {
  const page = await browser.newPage(); const s = newState(); s.group = true; s.scorer = OPP;
  s.cards = GROUP_OWNERS.map((uid, i) => ({ id: "card" + (i + 1), user_id: uid, course_name: "Pebble Beach Golf Links", matchup_id: MID, status: "in_progress",
    course_pars: null, course_yardages: null, scores: Array.from({ length: 18 }, (_, h) => (h < 3 ? 4 + (i % 2) : null)) }));
  await mockApi(page, s);
  await signInAndOpenMatch(page);

  await page.getByText("Olive Opp is keeping score for this group").waitFor();
  await page.getByRole("cell", { name: "Quinn Third" }).waitFor();          // every player's card is visible
  assert.equal(await page.getByRole("button", { name: "Start scorecard" }).count(), 0, "no second scorecard to start");
  assert.equal(await page.getByRole("button", { name: "I'll keep score for the group" }).count(), 0, "cannot take over");
  assert.equal(await page.getByRole("button", { name: "Step down" }).count(), 0, "only the scorer sees the controls");
  if (process.env.E2E_SHOT_DIR) await page.screenshot({ path: `${process.env.E2E_SHOT_DIR}/group-watcher.png`, fullPage: true });
  assert.equal(s.rpc.filter((r) => r.name === "set_hole_score").length, 0, "watching writes nothing");
  await page.close();
});
