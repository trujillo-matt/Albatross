import { test } from "node:test";
import assert from "node:assert/strict";
import { cardOwners, foursomeOf, orderCards, nextEmptyCell, groupComplete, groupHasAllCards, sideOf } from "./groupScoring.ts";

const blank = () => Array<number | null>(18).fill(null);
const m = (type: "best_ball" | "scramble", a: string[], b: string[]) => ({ match_type: type, team_a_player_ids: a, team_b_player_ids: b }) as never;

test("best ball: one card per player, side A first", () => {
  assert.deepEqual(cardOwners(m("best_ball", ["a1", "a2"], ["b1", "b2"])), ["a1", "a2", "b1", "b2"]);
});
test("scramble: one card per side, owned by the first player listed", () => {
  assert.deepEqual(cardOwners(m("scramble", ["a1", "a2"], ["b1", "b2"])), ["a1", "b1"]);
});
test("singles: two cards", () => {
  assert.deepEqual(cardOwners(m("best_ball", ["a1"], ["b1"])), ["a1", "b1"]);
});
test("orderCards follows owner order and ignores strangers", () => {
  const mm = m("best_ball", ["a1", "a2"], ["b1"]);
  const got = orderCards(mm, [{ user_id: "b1" }, { user_id: "zz" }, { user_id: "a2" }, { user_id: "a1" }]);
  assert.deepEqual(got.map((c) => c.user_id), ["a1", "a2", "b1"]);
});
test("groupHasAllCards needs every owner", () => {
  const mm = m("best_ball", ["a1"], ["b1"]);
  assert.equal(groupHasAllCards(mm, [{ user_id: "a1" }]), false);
  assert.equal(groupHasAllCards(mm, [{ user_id: "a1" }, { user_id: "b1" }]), true);
});
test("sideOf", () => {
  const mm = m("best_ball", ["a1"], ["b1"]);
  assert.equal(sideOf(mm, "a1"), "A"); assert.equal(sideOf(mm, "b1"), "B");
});

test("auto advance: next player on the same hole, then the next hole", () => {
  const cards = [{ scores: blank() }, { scores: blank() }, { scores: blank() }];
  cards[0].scores[0] = 4;
  assert.deepEqual(nextEmptyCell(cards, 0, 0), { hole: 0, card: 1 });
  cards[1].scores[0] = 5; cards[2].scores[0] = 4;
  assert.deepEqual(nextEmptyCell(cards, 0, 2), { hole: 1, card: 0 });
});
test("auto advance skips cells that are already filled", () => {
  const cards = [{ scores: blank() }, { scores: blank() }];
  cards[0].scores[0] = 4; cards[1].scores[0] = 4; cards[1].scores[1] = 4;
  assert.deepEqual(nextEmptyCell(cards, 0, 1), { hole: 1, card: 0 });
});
test("auto advance wraps to an earlier gap", () => {
  const cards = [{ scores: Array<number | null>(18).fill(4) }, { scores: Array<number | null>(18).fill(4) }];
  cards[0].scores[2] = null;
  assert.deepEqual(nextEmptyCell(cards, 17, 1), { hole: 2, card: 0 });
});
test("auto advance returns null when everything is filled", () => {
  const cards = [{ scores: Array<number | null>(18).fill(4) }];
  assert.equal(nextEmptyCell(cards, 5, 0), null);
  assert.equal(groupComplete(cards), true);
  assert.equal(nextEmptyCell([], 0, 0), null);
});
test("a group is not complete with one hole missing", () => {
  const cards = [{ scores: Array<number | null>(18).fill(4) }, { scores: Array<number | null>(18).fill(4) }];
  cards[1].scores[17] = null;
  assert.equal(groupComplete(cards), false);
});

const single = (n: number, type: "match_play" | "best_ball", session: string | null, a: string, b: string) =>
  ({ id: `m${n}`, matchup_number: n, session_id: session, match_type: type, team_a_player_ids: [a], team_b_player_ids: [b] }) as never as import("./types").TMatchup;

test("foursome: singles matches in a session are played two at a time", () => {
  const all = [1, 2, 3, 4, 5].map((n) => single(n, "match_play", "s1", `a${n}`, `b${n}`));
  assert.deepEqual(foursomeOf(all[0], all).map((x) => x.id), ["m1", "m2"]);
  assert.deepEqual(foursomeOf(all[1], all).map((x) => x.id), ["m1", "m2"]);
  assert.deepEqual(foursomeOf(all[2], all).map((x) => x.id), ["m3", "m4"]);
  assert.deepEqual(foursomeOf(all[4], all).map((x) => x.id), ["m5"]);
});
test("foursome: a pairs match is already a foursome, and so is a match outside a session", () => {
  const bb = single(1, "best_ball", "s1", "a1", "b1");
  assert.deepEqual(foursomeOf(bb, [bb, single(2, "best_ball", "s1", "a2", "b2")]).map((x) => x.id), ["m1"]);
  const loose = single(1, "match_play", null, "a1", "b1");
  assert.deepEqual(foursomeOf(loose, [loose, single(2, "match_play", null, "a2", "b2")]).map((x) => x.id), ["m1"]);
});
test("foursome: one scorer owns the cards of both matches", () => {
  const all = [1, 2].map((n) => single(n, "match_play", "s1", `a${n}`, `b${n}`));
  assert.deepEqual(cardOwners(foursomeOf(all[0], all)), ["a1", "b1", "a2", "b2"]);
});

import { applyPending, cardsCacheKey } from "./groupScoring.ts";
test("pending scores are laid over cached or fetched cards, last write per hole last", () => {
  const cards = [{ id: "r1", scores: Array<number | null>(18).fill(null) }, { id: "r2", scores: Array<number | null>(18).fill(4) }];
  const out = applyPending(cards, [{ roundId: "r1", hole: 1, strokes: 5 }, { roundId: "r1", hole: 3, strokes: null }, { roundId: "r2", hole: 18, strokes: 7 }, { roundId: "other", hole: 2, strokes: 9 }]);
  assert.equal(out[0].scores[0], 5);
  assert.equal(out[0].scores[2], null);
  assert.equal(out[1].scores[17], 7);
  assert.equal(cards[0].scores[0], null);                       // the input is not changed
  assert.equal(applyPending(cards, []), cards);                  // nothing pending: same array back
  assert.equal(cardsCacheKey("a,b"), "albatross-group-cards:a,b");
});
