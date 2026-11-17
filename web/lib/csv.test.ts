import { test } from "node:test";
import assert from "node:assert/strict";
import { csvCell, toCsv } from "./csv.ts";

test("quotes commas, quotes and newlines", () => {
  assert.equal(csvCell('a,"b"'), '"a,""b"""');
  assert.equal(csvCell("x\ny"), '"x\ny"');
});
test("keeps plain numbers, including negatives", () => {
  assert.equal(csvCell(-3), "-3");
  assert.equal(csvCell(4.5), "4.5");
});
test("neutralizes formula injection in text", () => {
  assert.equal(csvCell("=SUM(A1)"), "'=SUM(A1)");
  assert.equal(csvCell("@cmd"), "'@cmd");
});
test("joins rows with CRLF", () => {
  assert.equal(toCsv([["a", 1], ["b", null]]), "a,1\r\nb,\r\n");
});
