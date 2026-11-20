import { test } from "node:test";
import assert from "node:assert/strict";
import { normalizeCode, formatCode } from "./code.ts";

test("normalizes case, separators and look-alikes", () => {
  assert.equal(normalizeCode("k7m2-9qxh"), "K7M29QXH");
  assert.equal(normalizeCode("Ko1l-2345"), "K0112345");
  assert.equal(normalizeCode("O0Il"), "0011");
});
test("formats 8 char codes with a dash", () => {
  assert.equal(formatCode("K7M29QXH"), "K7M2-9QXH");
});
