// The charts' line geometry (julia/viewer/static/charts.mjs): an undefined value (null in the series JSON, NaN in a
// frame's Lorenz curve) is a gap in the line, never a point at 0; the axes take every defined value and only those.
import { test } from "node:test";
import assert from "node:assert/strict";

import { CHARTS, linePath, xMax, yTop } from "../../viewer/static/charts.mjs";

const xOf = (i) => 10 * i;
const yOf = (v) => 100 - 10 * v; // y of 0 is 100

test("linePath splits at null: [1, null, 2, 3] gives two segments", () => {
  const segments = linePath([1, null, 2, 3], xOf, yOf);
  assert.deepEqual(segments, [[[0, 90]], [[20, 80], [30, 70]]]);
});

test("no segment passes through y of 0 for the null", () => {
  for (const seg of linePath([1, null, 2, 3], xOf, yOf)) {
    for (const [x, y] of seg) {
      assert.notEqual(x, 10);
      assert.notEqual(y, yOf(0));
    }
  }
});

test("NaN and undefined are gaps too; leading, trailing and repeated gaps give no empty segment", () => {
  assert.deepEqual(linePath([null, NaN, 4, undefined, null, 5, null], xOf, yOf), [[[20, 60]], [[50, 50]]]);
  assert.deepEqual(linePath([], xOf, yOf), []);
  assert.deepEqual(linePath([null, null], xOf, yOf), []);
  assert.deepEqual(linePath(new Float64Array([0, NaN, 0.5]), xOf, yOf), [[[0, 100]], [[20, 95]]]); // a real 0 is drawn
});

test("yTop covers the largest defined value and ignores the undefined ones", () => {
  assert.equal(yTop([[null, 3, 7], [NaN, 2]]), 10);
  assert.equal(yTop([[null, null]]), 1);
  assert.equal(yTop([[0, 0]]), 1);
  assert.equal(yTop([[0.3]]), 0.5);
  assert.equal(yTop([[12000]]), 20000);
});

test("xMax: periods 0 to newest on a nice scale that reaches 500 (the study's end) once the run gets there", () => {
  assert.equal(xMax(0), 10);
  assert.equal(xMax(10), 10);
  assert.equal(xMax(11), 20);
  assert.equal(xMax(130), 200);
  assert.equal(xMax(499), 500);
  assert.equal(xMax(501), 1000);
});

test("the seven charts of the spec draw the server's series keys", () => {
  assert.equal(CHARTS.length, 7);
  const keys = CHARTS.flatMap((c) => c.panels.flatMap((p) => p.lines.map((l) => l.key)));
  assert.deepEqual(keys.sort(), [
    "fraction_sick", "gini", "killed_blue", "killed_red", "mean_price", "n_blue", "n_loans", "n_red", "total_debt",
    "trades", "tribe_changes",
  ]);
});
