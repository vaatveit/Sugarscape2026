import { test } from "node:test";
import assert from "node:assert/strict";

import { pause } from "../../viewer/static/pace.mjs";

const timed = async (promise) => {
  const start = performance.now();
  await promise;
  return performance.now() - start;
};

test("max speed moves on without waiting for a screen redraw", async () => {
  // Node has no requestAnimationFrame, like a hidden page whose redraws never come; playback stalled there.
  assert.equal(typeof globalThis.requestAnimationFrame, "undefined");
  for (let i = 0; i < 100; i++) assert.ok((await timed(pause("max", 0))) < 50);
});

test("a set speed waits out the rest of the period", async () => {
  const took = await timed(pause("10", 30)); // 100 ms per period, 30 already spent
  assert.ok(took >= 60 && took < 200, `took ${took} ms`);
});

test("a period that already overran its share does not wait", async () => {
  assert.ok((await timed(pause("10", 150))) < 50);
});
