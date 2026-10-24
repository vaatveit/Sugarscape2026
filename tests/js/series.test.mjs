import { test } from "node:test";
import assert from "node:assert/strict";

import { PopulationSeries } from "../../viewer/static/series.mjs";

test("a very long run neither throws nor loses its maximum", () => {
  // Math.max(...counts) and push(...counts) overflow the call stack from about 150,000 periods.
  const n = 500_000;
  const counts = Array.from({ length: n }, (_, t) => (t === 123_456 ? 4321 : t % 1000));
  const series = new PopulationSeries();
  assert.equal(series.append(0, counts), true);
  assert.equal(series.length, n);
  assert.equal(series.max, 4321);
  assert.equal(series.at(123_456), 4321);
  assert.equal(series.at(n - 1), (n - 1) % 1000);
});

test("appends in order, ignores chunks that don't continue the series", () => {
  const series = new PopulationSeries();
  assert.equal(series.max, 0);
  assert.equal(series.length, 0);
  assert.equal(series.append(0, [5, 9, 3]), true);
  assert.equal(series.append(2, [7]), false); // overlaps: from must equal the current length
  assert.equal(series.append(4, [7]), false); // leaves a gap
  assert.equal(series.append(3, [8, 1]), true);
  assert.deepEqual([0, 1, 2, 3, 4].map((t) => series.at(t)), [5, 9, 3, 8, 1]);
  assert.equal(series.length, 5);
  assert.equal(series.max, 9);
});
