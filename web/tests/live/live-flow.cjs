// Plays a full tournament through the real web UI against whatever Supabase project the running web app points at.
//
// WARNING: this WRITES to that project (a tournament, two managed player accounts, scorecards, audit rows). Use a
// staging project, or delete what it creates afterwards (see docs/LIVE_SCHEMA_AUDIT.md for the cleanup order: delete
// the tournament first, then the managed users, then the admin if it was throwaway).
//
// Usage (web app already running, e.g. `npm run build && npx next start -p 3000`):
//   E2E_ADMIN_EMAIL=... E2E_ADMIN_PASSWORD=... node tests/live/live-flow.cjs
// The admin account must already exist and be able to sign in with email and password. Screenshots go to ./shots.
const { chromium } = require("playwright");
const fs = require("fs"); const path = require("path");
const cfg = { email: process.env.E2E_ADMIN_EMAIL, password: process.env.E2E_ADMIN_PASSWORD };
if (!cfg.email || !cfg.password) { console.error("Set E2E_ADMIN_EMAIL and E2E_ADMIN_PASSWORD"); process.exit(2); }
const BASE = process.env.E2E_BASE || "http://localhost:3000";
const out = { ids: {}, steps: [] };
const step = (n) => { out.steps.push(n); console.log("STEP", n); };

(async () => {
  const proxy = process.env.HTTPS_PROXY ? { server: process.env.HTTPS_PROXY, bypass: "localhost,127.0.0.1" } : undefined;
  const browser = await chromium.launch({ proxy });
  const mk = async (name) => {
    const ctx = await browser.newContext({ viewport: { width: 420, height: 900 } });
    const page = await ctx.newPage(); page.setDefaultTimeout(25000);
    page.on("response", async (r) => {
      const u = r.url();
      if (u.includes("supabase.co") && r.status() >= 400 && !u.includes("/realtime/")) {
        let body = ""; try { body = (await r.text()).slice(0, 220); } catch {}
        console.log(`  [${name}] HTTP ${r.status()} ${new URL(u).pathname} ${body}`);
      }
    });
    page.on("pageerror", (e) => console.log(`  [${name}] pageerror:`, String(e).slice(0, 200)));
    return { ctx, page, name };
  };
  const shot = async (p, n) => p.page.screenshot({ path: path.join(__dirname, "shots", `${n}.png`), fullPage: true });
  const text = async (p) => (await p.page.locator("body").innerText()).replace(/\s+/g, " ").slice(0, 600);
  const tab = (p, t) => p.page.getByRole("button", { name: t, exact: true }).click();

  const admin = await mk("admin"), one = await mk("one"), two = await mk("two");
  let failed = null;
  try {
    // ---- admin signs in
    step("admin sign in");
    await admin.page.goto(`${BASE}/admin`);
    await admin.page.getByPlaceholder("Email").fill(cfg.email);
    await admin.page.getByPlaceholder("Password").fill(cfg.password);
    await admin.page.getByRole("button", { name: "Sign in" }).click();
    await admin.page.getByRole("heading", { name: "Your tournaments" }).waitFor();

    // ---- create tournament (1 match, stroke play, Pebble Beach)
    step("create tournament");
    await admin.page.getByRole("button", { name: "New tournament" }).click();
    await admin.page.getByPlaceholder(/Name, for example/).fill("E2E Test Cup");
    await admin.page.locator('input[type="number"]').fill("1");
    await admin.page.getByPlaceholder(/Course name/).fill("Pebble Beach Golf Links");
    await admin.page.locator("select").selectOption("stroke_play");
    await shot(admin, "01-create-form");
    await admin.page.getByRole("button", { name: "Create tournament" }).click();
    await admin.page.waitForURL(/\/admin\/[0-9a-f-]{36}$/);
    const tid = admin.page.url().split("/").pop(); out.ids.tournament = tid;
    await admin.page.getByRole("heading", { name: "E2E Test Cup" }).waitFor();

    // ---- roster: two managed players
    step("add managed players");
    await tab(admin, "Roster");
    await admin.page.locator("textarea").fill("E2E One\nE2E Two");
    await admin.page.getByRole("button", { name: "Create players and codes" }).click();
    await admin.page.locator("[data-code-card]").nth(1).waitFor({ timeout: 60000 });
    const cards = await admin.page.evaluate(() => [...document.querySelectorAll("[data-code-card]")].map((c) => ({
      name: c.getAttribute("data-player"), code: c.querySelector(".font-mono")?.textContent?.trim() })));
    const code = Object.fromEntries(cards.map((c) => [c.name, c.code]));
    if (!code["E2E One"] || !code["E2E Two"]) throw new Error("codes missing: " + JSON.stringify(cards.map((c) => c.name)));
    await shot(admin, "02-codes-issued");
    out.codesIssued = cards.length;

    // ---- start vote
    step("start captain vote");
    await tab(admin, "Overview");
    await admin.page.getByRole("button", { name: "Start captain vote and draft" }).click();
    await admin.page.getByText("Finalize on the Vote and draft tab").waitFor();

    // ---- players redeem codes
    for (const [p, nm] of [[one, "E2E One"], [two, "E2E Two"]]) {
      step(`redeem code: ${nm}`);
      await p.page.goto(`${BASE}/join`);
      await p.page.getByPlaceholder("XXXX-XXXX").fill(code[nm]);
      await p.page.getByRole("button", { name: "Continue" }).click();
      await p.page.waitForURL(`**/t/${tid}`);
      await p.page.getByRole("heading", { name: "Vote for captains" }).waitFor();
    }
    await shot(one, "03-player-vote");

    // ---- votes: One -> One,Two ; Two -> One,Admin ; Admin -> One,Two  => One 3, Two 2, Admin 1
    const vote = async (p, a, b) => {
      await p.page.getByRole("button", { name: new RegExp(a) }).first().click();
      await p.page.getByRole("button", { name: new RegExp(b) }).first().click();
      await p.page.getByRole("button", { name: /Submit votes \(2 of 2\)/ }).click();
      await p.page.getByText("Your vote is in").waitFor();
    };
    step("votes"); await vote(one, "E2E One", "E2E Two"); await vote(two, "E2E One", "E2E Admin");
    await admin.page.goto(`${BASE}/t/${tid}`); await admin.page.getByRole("heading", { name: "Vote for captains" }).waitFor();
    await vote(admin, "E2E One", "E2E Two");

    // ---- finalize captains
    step("finalize captains");
    await admin.page.goto(`${BASE}/admin/${tid}`); await tab(admin, "Vote and draft");
    await admin.page.getByRole("button", { name: "Finalize captains" }).click();
    await admin.page.getByText("Captain").first().waitFor();
    await shot(admin, "04-captains-final");

    // ---- captain One drafts the admin (pick 0 belongs to team A)
    step("captain drafts");
    await one.page.reload(); await one.page.getByRole("heading", { name: "Snake draft" }).waitFor();
    await one.page.getByRole("button", { name: /E2E Admin/ }).click();
    await one.page.getByText("All players are drafted").waitFor();
    await shot(one, "05-draft-done");

    // ---- start tournament, pair players
    step("start tournament");
    await admin.page.reload(); await tab(admin, "Vote and draft");
    const started = admin.page.waitForResponse((r) => r.url().includes("/tournament_matchups") && r.request().method() === "POST");
    await admin.page.getByRole("button", { name: "Start tournament" }).click();
    const sr = await started; if (sr.status() >= 300) throw new Error("matchups insert failed " + sr.status());
    step("set pairings");
    await admin.page.reload(); await tab(admin, "Matches");
    await admin.page.getByRole("button", { name: "E2E One" }).click();
    await admin.page.getByRole("button", { name: "E2E Two" }).click();
    const paired = admin.page.waitForResponse((r) => r.url().includes("/rpc/set_pairings"));
    await admin.page.getByRole("button", { name: "Confirm pairings" }).click();
    const pr = await paired; if (pr.status() >= 300) throw new Error("set_pairings failed " + pr.status() + " " + (await pr.text()).slice(0, 200));

    // ---- both players play 18 holes
    const play = async (p, score, nm) => {
      step(`play: ${nm}`);
      await p.page.reload();
      await p.page.getByText("Match 1").first().click();
      await p.page.getByRole("button", { name: "Start scorecard" }).click();
      await p.page.getByText(/Par \d · \d+ yds/).waitFor();     // real course data
      for (let h = 0; h < 18; h++) {
        await p.page.getByRole("button", { name: String(score), exact: true }).first().click();
        await p.page.waitForTimeout(300);
      }
      await p.page.getByText("18/18 holes").waitFor();
      await p.page.getByText("Synced", { exact: true }).waitFor({ timeout: 40000 });
      await shot(p, `06-card-${nm.replace(" ", "")}`);
      await p.page.getByRole("button", { name: "Finish and submit scorecard" }).click();
      await p.page.getByText("Scorecard submitted").waitFor();
    };
    await play(one, 4, "E2E One"); await play(two, 5, "E2E Two");

    // ---- result computed by the database trigger
    step("check result");
    await one.page.reload(); await one.page.getByText("Match 1").first().click();
    await one.page.getByText(/Final: 1\.0 to 0\.0/).waitFor({ timeout: 30000 });
    await one.page.goto(`${BASE}/t/${tid}`); await one.page.getByRole("button", { name: "Standings" }).click();
    await one.page.getByText("1.0").first().waitFor();
    await shot(one, "07-standings");

    // ---- admin: audited edit, recompute, audit tab
    step("admin edit + audit");
    admin.page.removeAllListeners("dialog"); let n = 0;
    admin.page.on("dialog", (d) => d.accept(n++ === 0 ? "3" : "e2e check"));
    await admin.page.goto(`${BASE}/admin/${tid}`); await tab(admin, "Scores");
    await admin.page.locator('[aria-label^="Edit hole"]').first().click();
    await admin.page.waitForTimeout(2500);
    await tab(admin, "Audit log");
    await admin.page.getByText("Edit hole score").waitFor();
    await shot(admin, "08-audit");

    // ---- spectator link
    step("spectator link");
    await tab(admin, "Overview");
    await admin.page.getByRole("button", { name: "Enable link" }).click();
    await admin.page.locator('input[readonly]').waitFor();
    const url = await admin.page.locator('input[readonly]').inputValue();
    const anon = await mk("spectator");
    await anon.page.goto(url.replace(/^https?:\/\/[^/]+/, BASE));
    await anon.page.getByRole("heading", { name: "E2E Test Cup" }).waitFor();
    await shot(anon, "09-spectator");
    out.ids.spectatorTokenLen = url.split("/").pop().length;
    step("DONE");
  } catch (e) {
    failed = e; console.log("FAILED at step:", out.steps[out.steps.length - 1]); console.log(String(e).split("\n").slice(0, 4).join("\n"));
    for (const p of [admin, one, two]) { try { await shot(p, `FAIL-${p.name}`); console.log(`  [${p.name}] page: ${await text(p)}`); } catch {} }
  }
  fs.writeFileSync(path.join(__dirname, "result.json"), JSON.stringify(out, null, 2));  // ids only, no secrets
  await browser.close(); process.exit(failed ? 1 : 0);
})();
