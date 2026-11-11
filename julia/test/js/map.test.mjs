// The map's fixed encodings (julia/viewer/static/map.mjs): the landscape blend, the agent colours by mode, the marks'
// fading and the hover read-out, on the fixture frame of frame.test.mjs.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import { decodeFrame } from "../../viewer/static/frame.mjs";
import {
  MODE_FIELDS, agentColour, hitTest, landscapeColour, markList, markOpacity, paintMap, tagString,
} from "../../viewer/static/map.mjs";

const here = new URL(".", import.meta.url);
const bytes = readFileSync(new URL("fixture-frame.bin", here));
const fixture = () => decodeFrame(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));

// The fixture frame moved to period t (its header's t field), for the marks of earlier periods.
function fixtureAt(t) {
  const ab = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
  new DataView(ab).setInt32(4, t, true);
  return decodeFrame(ab);
}

// A legend shaped as julia/viewer/encoding.jl's `legend` gives it, with distinct colours in every palette.
const hex = (k) => `#${k.toString(16).padStart(6, "0")}`;
const palette = (n, base) => Array.from({ length: n }, (_, i) => hex(base + 17 * i));
const legend = {
  modes: ["tribe", "culture", "wealth", "disease", "credit"],
  palettes: {
    tribe: ["#2563eb", "#c0392b"], culture: palette(12, 0x101010), wealth: palette(9, 0x202020),
    disease: palette(6, 0x303030), credit: palette(4, 0x404040),
  },
  max_level: 4,
  ntags: 11,
  mark_periods: 10,
  kill_colour: "#000000",
  change_colour: "#d4a000",
};

test("landscapeColour is one-to-one over every pair of levels in eighths up to maxLevel 4, and pale", () => {
  const seen = new Map();
  for (let s8 = 0; s8 <= 32; s8++) {
    for (let p8 = 0; p8 <= 32; p8++) {
      const rgb = landscapeColour(s8, p8, 4);
      assert.equal(rgb.length, 3);
      for (const c of rgb) {
        assert.ok(Number.isInteger(c) && c >= 150 && c <= 255, `channel ${c} at (${s8}, ${p8})`);
      }
      const key = rgb.join(",");
      assert.ok(!seen.has(key), `(${s8}, ${p8}) and ${seen.get(key)} share ${key}`);
      seen.set(key, `(${s8}, ${p8})`);
    }
  }
  assert.equal(seen.size, 33 * 33);
});

test("landscapeColour is fixed: the same levels give the same colour on every call, empty cells white", () => {
  assert.deepEqual(landscapeColour(0, 0, 4), [255, 255, 255]);
  assert.deepEqual(landscapeColour(17, 5, 4), landscapeColour(17, 5, 4));
  assert.throws(() => landscapeColour(33, 0, 4), RangeError); // above the landscape's capacity: not drawable
});

test("agentColour is the palette entry of the agent's code for each mode", () => {
  const f = fixture();
  assert.deepEqual(MODE_FIELDS, { tribe: "tribe", culture: "ones", wealth: "wealth", disease: "disease", credit: "role" });
  for (const mode of legend.modes) {
    for (let i = 0; i < f.n; i++) {
      const code = f.agents[MODE_FIELDS[mode]][i];
      assert.equal(agentColour(f, i, mode, legend), legend.palettes[mode][code], `${mode}, agent ${i}`);
    }
  }
  assert.equal(agentColour(f, 0, "tribe", legend), "#2563eb");
  assert.equal(agentColour(f, 1, "tribe", legend), "#c0392b");
});

test("markOpacity falls linearly over 10 periods", () => {
  assert.equal(markOpacity(0), 1);
  assert.ok(Math.abs(markOpacity(9) - 0.1) < 1e-12);
  assert.ok(Math.abs(markOpacity(5) - 0.5) < 1e-12);
  assert.equal(markOpacity(10), 0);
  assert.equal(markOpacity(25), 0);
  assert.equal(markOpacity(-1), 0);
});

test("markList: each kept frame of the last 10 periods gives its kills and changes, with their age", () => {
  const shown = fixtureAt(20);
  const marks = markList(shown, [fixtureAt(14), fixtureAt(10), fixtureAt(21), shown]);
  const byAge = (age, kind) => marks.filter((m) => m.age === age && m.kind === kind);
  assert.deepEqual(byAge(0, "kill").map((m) => [m.x, m.y]), [[1, 1]]); // the shown frame, once
  assert.deepEqual(byAge(0, "change").map((m) => [m.x, m.y]), [[2, 0]]);
  assert.equal(byAge(6, "kill").length, 1);
  assert.equal(byAge(6, "kill")[0].opacity, markOpacity(6));
  assert.equal(marks.filter((m) => m.age >= 10 || m.age < 0).length, 0); // t = 10 is too old, t = 21 is later
  assert.equal(marks.length, 4);
  assert.ok(marks.findIndex((m) => m.age === 6) < marks.findIndex((m) => m.age === 0)); // newest drawn last
});

test("paintMap: one pixel per cell, y increasing upward, agents in their mode's colour over the landscape", () => {
  const f = fixture();
  f.cellSugar8[5] = 32; // the fixture's 255 eighths is above maxLevel 4
  const image = paintMap(f, "tribe", legend);
  assert.equal(image.length, 3 * 2 * 4);
  const pixel = (x, y) => Array.from(image.slice(((f.height - 1 - y) * f.width + x) * 4, ((f.height - 1 - y) * f.width + x) * 4 + 4));
  assert.deepEqual(pixel(0, 1), [0x25, 0x63, 0xeb, 255]); // agent 0, blue, at (0, 1): the top-left pixel
  assert.deepEqual(pixel(2, 0), [0xc0, 0x39, 0x2b, 255]); // agent 1, red, at (2, 0)
  assert.deepEqual(pixel(1, 0), [...landscapeColour(f.cellSugar8[1], f.cellSpice8[1], 4), 255]);
  assert.deepEqual(pixel(2, 1), [...landscapeColour(32, f.cellSpice8[5], 4), 255]);
});

test("tagString: tag i is bit i - 1, as the model stores tags", () => {
  assert.equal(tagString(165, 11), "10100101000");
  assert.equal(tagString(2047, 11), "11111111111");
  assert.equal(tagString(0, 11), "00000000000");
});

test("hitTest on an agent's cell gives its exact values and its tags as a string", () => {
  const f = fixture();
  const hit = hitTest(f, 0, 1);
  assert.equal(hit.agent.id, 5);
  assert.equal(hit.agent.sugar, 1.5);
  assert.equal(hit.agent.spice, 0.25);
  assert.equal(hit.agent.tags, "10100101000");
  assert.equal(hit.agent.age, 3);
  assert.equal(hit.agent.lent, 1);
  assert.equal(hit.agent.owed, 0);
  assert.equal(hit.agent.tribe, 0);
  assert.equal(hit.agent.ndiseases, 0);
  const other = hitTest(f, 2, 0);
  assert.equal(other.agent.id, 70000);
  assert.equal(other.agent.sugar, 20);
  assert.equal(other.agent.tags, "11111111111");
  assert.equal(other.agent.owed, 2);
  assert.equal(other.agent.ndiseases, 4);
});

test("hitTest on an empty cell gives its levels, eighths divided by 8", () => {
  const f = fixture();
  const hit = hitTest(f, 1, 0); // index y * width + x = 1
  assert.equal(hit.agent, undefined);
  assert.deepEqual(hit.cell, { x: 1, y: 0, sugar: 1, spice: 0.25 });
  assert.deepEqual(hitTest(f, 2, 1).cell, { x: 2, y: 1, sugar: 255 / 8, spice: 6 / 8 });
  assert.equal(hitTest(f, 3, 0), null);
  assert.equal(hitTest(f, 0, -1), null);
});
