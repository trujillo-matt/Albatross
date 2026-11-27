import { test } from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_TEAM_COLORS, fillByMatch, fillTeeTimes, fromLocalInput, groupTimes, groupsForSession, moveToNewTimes, teamColor, textOn, toLocalInput } from "./teams.ts";

test("a team with no colour gets the default for its side", () => {
  assert.equal(teamColor({ color: null, side: "A" }), DEFAULT_TEAM_COLORS.A);
  assert.equal(teamColor({ color: null, side: "B" }), DEFAULT_TEAM_COLORS.B);
  assert.equal(teamColor({ color: "#1D4E89", side: "A" }), "#1D4E89");
});
test("text is white on dark colours and black on light ones", () => {
  assert.equal(textOn("#006747"), "#FFFFFF");
  assert.equal(textOn("#FDE68A"), "#111111");
});
test("tee times fill in groups of four, ten minutes apart", () => {
  const ids = ["a", "b", "c", "d", "e", "f"];
  const got = fillTeeTimes(ids, "2026-11-21T08:00", 10, 4);
  assert.equal(got.a, "2026-11-21T08:00");
  assert.equal(got.d, "2026-11-21T08:00");
  assert.equal(got.e, "2026-11-21T08:10");
  assert.equal(got.f, "2026-11-21T08:10");
});
test("fill by match puts both sides of each match in one group, in match order", () => {
  const got = fillByMatch([
    { matchup_number: 2, team_a_player_ids: ["c", "d"], team_b_player_ids: ["g", "h"] },
    { matchup_number: 1, team_a_player_ids: ["a", "b"], team_b_player_ids: ["e", "f"] },
  ], "2026-11-21T08:00", 10);
  assert.deepEqual(got.times, ["2026-11-21T08:00", "2026-11-21T08:10"]);
  for (const id of ["a", "b", "e", "f"]) assert.equal(got.values[id], "2026-11-21T08:00");
  for (const id of ["c", "d", "g", "h"]) assert.equal(got.values[id], "2026-11-21T08:10");
});
test("local input values round trip", () => {
  const iso = fromLocalInput("2026-11-21T08:10");
  assert.ok(iso);
  assert.equal(toLocalInput(iso), "2026-11-21T08:10");
  assert.equal(fromLocalInput(""), null);
});
test("groups are the players sharing a tee time, earliest first", () => {
  const players = ["a", "b", "c"].map((id) => ({ user_id: id, display_name: id }) as never);
  const rows = [
    { session_id: "s", tournament_id: "t", user_id: "c", tee_time: "2026-11-21T09:00:00.000Z" },
    { session_id: "s", tournament_id: "t", user_id: "a", tee_time: "2026-11-21T08:00:00.000Z" },
    { session_id: "s", tournament_id: "t", user_id: "b", tee_time: "2026-11-21T08:00:00.000Z" },
    { session_id: "other", tournament_id: "t", user_id: "a", tee_time: "2026-11-22T08:00:00.000Z" },
  ];
  const groups = groupsForSession(rows, "s", players);
  assert.deepEqual(groups.map((g) => g.players.map((p) => p.user_id)), [["a", "b"], ["c"]]);
});

import { timeAgo } from "./labels.ts";
test("news times read as 'x minutes ago'", () => {
  const now = Date.parse("2026-11-22T12:00:00Z");
  assert.equal(timeAgo("2026-11-22T11:58:00Z", now), "2 minutes ago");
  assert.equal(timeAgo("2026-11-22T09:00:00Z", now), "3 hours ago");
  assert.equal(timeAgo("2026-11-22T11:59:50Z", now), "just now");
  assert.equal(timeAgo("2026-11-21T10:00:00Z", now), "yesterday");
});

test("group times step from the first tee time", () => {
  assert.deepEqual(groupTimes("2026-11-21T08:00", 10, 3), ["2026-11-21T08:00", "2026-11-21T08:10", "2026-11-21T08:20"]);
  assert.deepEqual(groupTimes("", 10, 3), []);
  assert.deepEqual(groupTimes("2026-11-21T08:00", 10, 0), []);
});

test("players keep their group when the times change", () => {
  const values = { a: "2026-11-21T08:00", b: "2026-11-21T08:00", c: "2026-11-21T08:10", d: "" };
  const moved = moveToNewTimes(values, ["2026-11-21T08:00", "2026-11-21T08:10"], ["2026-11-21T09:00", "2026-11-21T09:12"]);
  assert.deepEqual(moved, { a: "2026-11-21T09:00", b: "2026-11-21T09:00", c: "2026-11-21T09:12", d: "" });
  const fewer = moveToNewTimes(values, ["2026-11-21T08:00", "2026-11-21T08:10"], ["2026-11-21T09:00"]);
  assert.equal(fewer.c, "");
});
