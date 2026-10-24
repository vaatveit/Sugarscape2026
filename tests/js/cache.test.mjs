import { test } from "node:test";
import assert from "node:assert/strict";

import { CACHE_LIMIT, CACHE_LIMIT_XL, FrameCache } from "../../viewer/static/cache.mjs";

const fill = (cache, n) => {
  for (let t = 0; t < n; t++) cache.set(t, { t });
};

test("an xl cache holds at most 20 frames, a regular one 300", () => {
  assert.equal(CACHE_LIMIT_XL, 20);
  assert.equal(CACHE_LIMIT, 300);
  const xl = new FrameCache(true);
  const regular = new FrameCache(false);
  fill(xl, 25);
  fill(regular, 305);
  assert.equal(xl.size, 20);
  assert.equal(regular.size, 300);
});

test("the oldest frame added is the one dropped", () => {
  const cache = new FrameCache(true);
  fill(cache, 21);
  assert.equal(cache.has(0), false);
  assert.deepEqual(cache.get(1), { t: 1 });
  assert.deepEqual(cache.get(20), { t: 20 });
});

test("frames before the server's earliest kept period are dropped", () => {
  const cache = new FrameCache(false);
  fill(cache, 10);
  cache.dropBefore(4);
  assert.equal(cache.size, 6);
  assert.equal(cache.has(3), false);
  assert.equal(cache.has(4), true);
});
