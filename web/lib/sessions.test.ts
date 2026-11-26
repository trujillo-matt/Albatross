import { test } from "node:test";
import assert from "node:assert/strict";
import { calloutState, groupByDay, planToSessionRows, planTotals, isPointsSplit, playersPerSide, rosterWarning, sameUnit, sessionMatchCount, sitOuts, sideOf } from "./sessions.ts";
import type { TMatchup, TPlayer, TSession, TTeam } from "./types.ts";

const session = (o: Partial<TSession>): TSession => ({
  id: "s1", tournament_id: "t", day_number: 1, session_number: 1, label: null, match_type: "best_ball", course_name: null, course_id: null,
  match_count: 2, status: "lineup", first_caller_team_id: null, turn_team_id: null, consecutive_passes: 0, ...o,
});
const match = (o: Partial<TMatchup>): TMatchup => ({
  id: "m1", tournament_id: "t", matchup_number: 1, team_a_id: "A", team_b_id: "B", team_a_player_ids: [], team_b_player_ids: [],
  match_type: "best_ball", status: "pending", result: null, points_team_a: 0, points_team_b: 0, session_id: "s1", ...o,
});

test("players per side by format", () => {
  assert.equal(playersPerSide("match_play"), 1);
  assert.equal(playersPerSide("stroke_play"), 1);
  for (const f of ["best_ball", "scramble", "alternate_shot", "shamble"] as const) assert.equal(playersPerSide(f), 2);
});

test("match count comes from the smaller roster; extras sit out", () => {
  assert.equal(sessionMatchCount(12, 12, "match_play"), 12);
  assert.equal(sessionMatchCount(12, 12, "alternate_shot"), 6);
  assert.equal(sessionMatchCount(5, 4, "match_play"), 4);
  assert.equal(sessionMatchCount(4, 3, "best_ball"), 1);
  assert.equal(sessionMatchCount(1, 1, "best_ball"), 0);
});

test("plan totals match the database (points to win is more than half)", () => {
  const t = planTotals([{ match_type: "alternate_shot" }, { match_type: "best_ball" }], 8, 8);
  assert.deepEqual(t, { matches: 8, pointsToWin: 4.5 });
  assert.equal(planTotals([{ match_type: "match_play" }], 12, 12).pointsToWin, 6.5);
});

test("groupByDay orders days and sessions and attaches matches in order", () => {
  const days = groupByDay(
    [session({ id: "b", day_number: 2 }), session({ id: "a2", session_number: 2 }), session({ id: "a1" })],
    [match({ id: "x2", matchup_number: 2, session_id: "a1" }), match({ id: "x1", matchup_number: 1, session_id: "a1" })],
  );
  assert.deepEqual(days.map((d) => d.day), [1, 2]);
  assert.deepEqual(days[0].sessions.map((s) => s.session.id), ["a1", "a2"]);
  assert.deepEqual(days[0].sessions[0].matchups.map((m) => m.id), ["x1", "x2"]);
});

test("sit-outs are accepted team players in none of the session's matches", () => {
  const team = { id: "A" } as TTeam;
  const p = (user_id: string, team_id: string, invite_status: TPlayer["invite_status"] = "accepted") => ({ user_id, team_id, invite_status }) as TPlayer;
  const out = sitOuts(team, [p("1", "A"), p("2", "A"), p("3", "A"), p("4", "A", "declined"), p("9", "B")], [match({ team_a_player_ids: ["1", "2"] })], "A");
  assert.deepEqual(out.map((x) => x.user_id), ["3"]);
});

test("callout state: whose turn, open vs locked, and when a pass locks everything", () => {
  const ms = [match({ id: "1", called_at: "2026-01-01" }), match({ id: "2" }), match({ id: "3" })];
  const s = calloutState(session({ status: "callouts", turn_team_id: "B", consecutive_passes: 1 }), ms);
  assert.equal(s.turnTeamId, "B");
  assert.equal(s.openMatches, 2);
  assert.equal(s.lockedMatches, 1);
  assert.equal(s.nextPassLocks, true);
  assert.equal(calloutState(session({ status: "lineup", turn_team_id: "B" }), ms).turnTeamId, null);
});

test("side is the canonical A/B order, never row order", () => {
  const teams = [{ id: "y", name: "Y", side: "B" }, { id: "x", name: "X", side: "A" }] as TTeam[];
  assert.equal(sideOf(teams, "x"), "A");
  assert.equal(sideOf(teams, "y"), "B");
  assert.equal(sideOf(teams, "z"), null);
});

test("sameUnit ignores order", () => {
  assert.ok(sameUnit(["a", "b"], ["b", "a"]));
  assert.ok(!sameUnit(["a"], ["a", "b"]));
});

test("plan rows number days and sessions from 1", () => {
  const rows = planToSessionRows("t", [
    { course: "Pebble", sessions: [{ label: "AM", match_type: "scramble" }, { label: " ", match_type: "alternate_shot" }] },
    { course: "", sessions: [{ label: "Singles", match_type: "match_play" }] },
  ]);
  assert.deepEqual(rows.map((r) => [r.day_number, r.session_number, r.label, r.course_name]), [[1, 1, "AM", "Pebble"], [1, 2, null, "Pebble"], [2, 1, "Singles", null]]);
});

test("course for a match: session course, then the day's course, then the old round-per-match row", async () => {
  const { courseForMatch } = await import("./sessions.ts");
  const courses = [{ round_number: 1, course_name: "Day one", course_id: "c1" }, { round_number: 3, course_name: "Legacy third", course_id: null }] as never;
  const sessions = [session({ id: "withCourse", course_name: "Own", course_id: "x" }), session({ id: "noCourse", day_number: 1, course_name: null })];
  const data = { sessions, courses };
  assert.deepEqual(courseForMatch(data, match({ session_id: "withCourse" })), { name: "Own", id: "x" });
  assert.deepEqual(courseForMatch(data, match({ session_id: "noCourse" })), { name: "Day one", id: "c1" });
  assert.deepEqual(courseForMatch(data, match({ session_id: null, matchup_number: 3 })), { name: "Legacy third", id: null });
});

test("alternate shot is scored on one team card like scramble (lowest total wins)", async () => {
  const { matchPoints } = await import("./scoring.ts");
  const card = (n: number) => Array.from({ length: 18 }, () => n);
  assert.deepEqual(matchPoints("alternate_shot", [card(4)], [card(5)]), { a: 1, b: 0 });
  assert.deepEqual(matchPoints("alternate_shot", [card(5)], [card(5)]), { a: 0.5, b: 0.5 });
});

test("shamble is scored like best ball: lower of the two scores per hole, lowest total wins", async () => {
  const { matchPoints } = await import("./scoring.ts");
  const { isTeamCardFormat, cardOwners } = await import("./groupScoring.ts");
  const card = (n: number) => Array.from({ length: 18 }, () => n);
  // A has a 4 card and a 6 card (best 4 every hole = 72), B has two 5 cards (90)
  assert.deepEqual(matchPoints("shamble", [card(4), card(6)], [card(5), card(5)]), { a: 1, b: 0 });
  assert.deepEqual(matchPoints("shamble", [card(6), card(5)], [card(5), card(6)]), { a: 0.5, b: 0.5 });
  assert.deepEqual(matchPoints("shamble", [card(5), card(5)], [card(4), card(7)]), { a: 0, b: 1 });
  // one card per player, not one per side
  assert.equal(isTeamCardFormat("shamble"), false);
  const m = { match_type: "shamble", team_a_player_ids: ["a1", "a2"], team_b_player_ids: ["b1", "b2"] } as never;
  assert.deepEqual(cardOwners(m), ["a1", "a2", "b1", "b2"]);
});

test("a roster outside 24 to 28 gets a warning, inside gets none", () => {
  assert.equal(rosterWarning(24), null);
  assert.equal(rosterWarning(26), null);
  assert.equal(rosterWarning(28), null);
  assert.match(rosterWarning(23) ?? "", /23 players.*1 more is needed/);
  assert.match(rosterWarning(20) ?? "", /4 more are needed/);
  assert.match(rosterWarning(30) ?? "", /30 players, 2 over the 28/);
});

test("a points split needs every match finished and level points", () => {
  const done = (a: number, b: number) => ({ status: "complete" as const, points_team_a: a, points_team_b: b });
  assert.equal(isPointsSplit([]), false);
  assert.equal(isPointsSplit([done(1, 0), done(0, 1)]), true);
  assert.equal(isPointsSplit([done(0.5, 0.5), done(1, 0), done(0, 1)]), true);
  assert.equal(isPointsSplit([done(1, 0), done(1, 0)]), false);
  assert.equal(isPointsSplit([done(1, 0), { status: "active" as const, points_team_a: 0, points_team_b: 0 }]), false);
});
