import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";

// A tiny localStorage so the queue can run under node.
const store = new Map<string, string>();
(globalThis as unknown as { localStorage: Storage }).localStorage = {
  getItem: (k: string) => store.get(k) ?? null,
  setItem: (k: string, v: string) => { store.set(k, v); },
} as Storage;

const { enqueue, flush, isServerRejection, pendingCount } = await import("./scoreQueue.ts");
const ok = async () => ({ error: null });
const fail = (message: string, code?: string) => async () => ({ error: { message, code } });

beforeEach(() => store.clear());

test("only a clear server refusal counts as a rejection", () => {
  assert.equal(isServerRejection({ code: "P0001", message: "round not found, not yours, or already completed" }), true);
  assert.equal(isServerRejection({ code: "P0001", message: "a scorer is keeping score for this group" }), true);
  assert.equal(isServerRejection({ code: "P0001", message: "strokes must be 1 to 20" }), true);
  // sign-in problems, no signal, server trouble and unknown errors are not rejections
  assert.equal(isServerRejection({ code: "P0001", message: "not signed in" }), false);
  assert.equal(isServerRejection({ code: "PGRST301", message: "JWT expired" }), false);
  assert.equal(isServerRejection({ message: "TypeError: Failed to fetch" }), false);
  assert.equal(isServerRejection({ code: "42501", message: "permission denied for function set_hole_score" }), false);
  assert.equal(isServerRejection({ code: "P0001", message: "something new" }), false);
});

test("an expired sign-in keeps every score queued and reports why", async () => {
  enqueue({ roundId: "r1", hole: 1, strokes: 4 });
  enqueue({ roundId: "r1", hole: 2, strokes: 5 });
  const result = await flush(fail("JWT expired", "PGRST301"));
  assert.equal(result.sent, 0);
  assert.deepEqual(result.rejected, []);
  assert.equal(result.stalled, "JWT expired");
  assert.equal(pendingCount(), 2);
  // once the sign-in is back, the same scores go through in order
  const sentHoles: number[] = [];
  const again = await flush(async (item) => { sentHoles.push(item.hole); return { error: null }; });
  assert.deepEqual(sentHoles, [1, 2]);
  assert.equal(again.sent, 2);
  assert.equal(pendingCount(), 0);
});

test("a rejected score is dropped and the rest still go", async () => {
  enqueue({ roundId: "r1", hole: 1, strokes: 4 });
  enqueue({ roundId: "r2", hole: 1, strokes: 5 });
  const result = await flush(async (item) => item.roundId === "r1"
    ? { error: { code: "P0001", message: "round not found, not yours, or already completed" } }
    : { error: null });
  assert.equal(result.sent, 1);
  assert.equal(result.rejected.length, 1);
  assert.equal(result.stalled, null);
  assert.equal(pendingCount(), 0);
});

test("a failure stops the flush so order is kept", async () => {
  enqueue({ roundId: "r1", hole: 1, strokes: 4 });
  enqueue({ roundId: "r1", hole: 2, strokes: 5 });
  enqueue({ roundId: "r1", hole: 3, strokes: 3 });
  let calls = 0;
  const result = await flush(async () => (++calls === 1 ? { error: null } : { error: { message: "TypeError: Failed to fetch" } }));
  assert.equal(result.sent, 1);
  assert.equal(pendingCount(), 2);
  assert.equal(calls, 2);   // stopped at the second, did not skip ahead
});

test("a thrown error leaves the queue intact and the next flush can run", async () => {
  enqueue({ roundId: "r1", hole: 1, strokes: 4 });
  const result = await flush(async () => { throw new Error("offline"); });
  assert.equal(result.stalled, "offline");
  assert.equal(pendingCount(), 1);
  assert.equal((await flush(ok)).sent, 1);
});
