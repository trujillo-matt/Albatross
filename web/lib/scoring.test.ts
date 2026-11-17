import { test } from "node:test";
import assert from "node:assert/strict";
import { matchPlayPoints, bestBallPoints, strokePlayPoints, matchPlayStatus } from "./scoring.ts";
import { snakeIsTeamATurn, defaultPointsToWin } from "./draft.ts";

const full = (n: number) => Array<number | null>(18).fill(n);

test("match play: more holes won takes the point", () => {
  const a = full(4), b = full(5);
  assert.deepEqual(matchPlayPoints([a], [b]), { a: 1, b: 0 });
});
test("match play: halved match is 0.5 each", () => {
  const a = [...full(4)]; const b = [...full(4)];
  assert.deepEqual(matchPlayPoints([a], [b]), { a: 0.5, b: 0.5 });
});
test("match play uses best ball per hole across a side", () => {
  const a1 = full(5), a2 = full(3), b = full(4);
  assert.deepEqual(matchPlayPoints([a1, a2], [b]), { a: 1, b: 0 });
});
test("match play skips holes either side has not scored", () => {
  const a = full(4).map((v, i) => (i < 9 ? v : null));
  const b = full(5);
  assert.deepEqual(matchPlayStatus([a], [b]), { up: 9, thru: 9 });
});
test("best ball: lower combined total wins", () => {
  assert.deepEqual(bestBallPoints([full(4), full(5)], [full(5)]), { a: 1, b: 0 });
  assert.deepEqual(bestBallPoints([full(4)], [full(4)]), { a: 0.5, b: 0.5 });
});
test("stroke play: lowest single total per side", () => {
  assert.deepEqual(strokePlayPoints([full(4), full(6)], [full(5)]), { a: 1, b: 0 });
});
test("snake order is A B B A A B B A", () => {
  const order = Array.from({ length: 8 }, (_, i) => (snakeIsTeamATurn(i) ? "A" : "B")).join("");
  assert.equal(order, "ABBAABBA");
});
test("points to win is a majority of available points", () => {
  assert.equal(defaultPointsToWin(3), 2);
  assert.equal(defaultPointsToWin(4), 2.5);
});
