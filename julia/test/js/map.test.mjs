// The map's fixed encodings (julia/viewer/static/map.mjs): the landscape blend, the agent colours by mode, the marks'
// fading and the hover read-out, on the fixture frame of frame.test.mjs.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import { decodeFrame } from "../../viewer/static/frame.mjs";
import {
  GROUNDS, MARK_WHEN, MARK_WHICH, MODE_FIELDS, agentColour, groundFor, groundsFor, hitTest, landscapeColour,
  markOpacity, markPeriods, marksNote, marksOverlap, marksToDraw, missingMarkPeriods, paintMap, paintMarks, tagString,
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

test("the marks menus: when (this period by default, fading, none) and which (both by default, kills, switches)", () => {
  assert.deepEqual(MARK_WHEN.map((o) => o.value), ["now", "fading", "none"]);
  assert.deepEqual(MARK_WHEN.map((o) => o.label), ["this period", "last 10 periods, fading", "none"]);
  assert.deepEqual(MARK_WHICH.map((o) => o.value), ["both", "kills", "switches"]);
  assert.deepEqual(MARK_WHICH.map((o) => o.label), ["kills and switches", "kills only", "switches only"]);
});

test("markPeriods: 'this period' and 'none' need only the shown frame; 'fading' the kept ones of the last 10", () => {
  assert.deepEqual(markPeriods(20, "now", 0), [20]);
  assert.deepEqual(markPeriods(20, "now", 15), [20]);
  assert.deepEqual(markPeriods(20, "none", 0), [20]);
  assert.deepEqual(markPeriods(20, "fading", 0), [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
  assert.deepEqual(markPeriods(20, "fading", 15), [15, 16, 17, 18, 19, 20]);
  assert.deepEqual(markPeriods(3, "fading", 0), [0, 1, 2, 3]);
  assert.deepEqual(markPeriods(0, "fading", null), [0]);
});

// The fixture's one kill is at (1, 1) and its one tribe change at (2, 0), in every copy moved to another period.
const KILL = { kind: "kill", x: 1, y: 1 };
const CHANGE = { kind: "change", x: 2, y: 0 };
const drawn = (marks) => marks.map(({ kind, x, y, age, opacity }) => ({ kind, x, y, age, opacity }));

test("marksToDraw, this period: only the shown period's events, opaque, whatever earlier frames are given", () => {
  const frames = [fixtureAt(14), fixtureAt(20), fixtureAt(19), fixtureAt(21)];
  assert.deepEqual(drawn(marksToDraw(20, "now", "both", frames)),
    [{ ...CHANGE, age: 0, opacity: 1 }, { ...KILL, age: 0, opacity: 1 }]); // switches first, kills on top
  assert.deepEqual(drawn(marksToDraw(20, "now", "kills", frames)), [{ ...KILL, age: 0, opacity: 1 }]);
  assert.deepEqual(drawn(marksToDraw(20, "now", "switches", frames)), [{ ...CHANGE, age: 0, opacity: 1 }]);
  assert.deepEqual(marksToDraw(20, "now", "both", [fixtureAt(20)]), marksToDraw(20, "now", "both", frames));
  assert.deepEqual(marksToDraw(20, "now", "both", [fixtureAt(19)]), []); // the shown frame itself carries them
});

test("marksToDraw, last 10 periods fading: ages 0 to 9 at 1 - age / 10, oldest first, each frame once", () => {
  const frames = [fixtureAt(20), fixtureAt(14), fixtureAt(10), fixtureAt(21), fixtureAt(20), fixtureAt(11)];
  assert.deepEqual(drawn(marksToDraw(20, "fading", "both", frames)), [
    { ...CHANGE, age: 9, opacity: markOpacity(9) }, { ...KILL, age: 9, opacity: markOpacity(9) },
    { ...CHANGE, age: 6, opacity: markOpacity(6) }, { ...KILL, age: 6, opacity: markOpacity(6) },
    { ...CHANGE, age: 0, opacity: 1 }, { ...KILL, age: 0, opacity: 1 },
  ]); // oldest period first, switches then kills within each; t = 10 is 10 periods old and t = 21 later: not drawn
  assert.deepEqual(drawn(marksToDraw(20, "fading", "kills", frames)), [
    { ...KILL, age: 9, opacity: markOpacity(9) }, { ...KILL, age: 6, opacity: markOpacity(6) }, { ...KILL, age: 0, opacity: 1 },
  ]);
  assert.deepEqual(drawn(marksToDraw(20, "fading", "switches", frames)), [
    { ...CHANGE, age: 9, opacity: markOpacity(9) }, { ...CHANGE, age: 6, opacity: markOpacity(6) },
    { ...CHANGE, age: 0, opacity: 1 },
  ]);
});

test("marksToDraw, none: no marks for any filter", () => {
  const frames = [fixtureAt(20), fixtureAt(19)];
  for (const which of ["both", "kills", "switches"]) assert.deepEqual(marksToDraw(20, "none", which, frames), []);
});

test("a mark changes exactly its own cell's pixels, none of its neighbours'", () => {
  const f = fixture();
  f.cellSugar8[5] = 32;
  for (const which of ["both", "kills", "switches"]) {
    const marks = marksToDraw(f.t, "now", which, [f]);
    const before = paintMap(f, "tribe", realLegend);
    const after = paintMarks(paintMap(f, "tribe", realLegend), f, marks, realLegend);
    const marked = new Set(marks.map((m) => `${m.x},${m.y}`));
    for (let y = 0; y < f.height; y++) {
      for (let x = 0; x < f.width; x++) {
        const k = ((f.height - 1 - y) * f.width + x) * 4;
        const px = (img) => Array.from(img.slice(k, k + 4));
        if (!marked.has(`${x},${y}`)) {
          assert.deepEqual(px(after), px(before), `${which}: cell (${x}, ${y}) changed`);
        } else {
          const m = marks.find((q) => q.x === x && q.y === y);
          const colour = m.kind === "kill" ? realLegend.kill_colour : realLegend.change_colour;
          assert.deepEqual(px(after), [...rgb(colour), 255], `${which}: cell (${x}, ${y})`);
        }
      }
    }
  }
  // The change at (2, 0) is on agent 1's cell: an opaque mark hides the agent there (hover still reads it).
  assert.equal(hitTest(f, 2, 0).agent.id, 70000);
});

// A period's events as a frame carries them: only t, kills and changes are read by the marks functions.
const events = (t, kills, changes) => ({
  t,
  kills: { x: kills.map((c) => c[0]), y: kills.map((c) => c[1]) },
  changes: { x: changes.map((c) => c[0]), y: changes.map((c) => c[1]) },
});

test("marksOverlap: nothing to say when every drawn event has its own cell", () => {
  const f = events(193, [[1, 1], [5, 5]], [[2, 2], [3, 3]]);
  for (const which of ["both", "kills", "switches"]) assert.equal(marksOverlap(193, "now", which, [f]), "");
  assert.equal(marksOverlap(193, "none", "both", [events(193, [[1, 1], [1, 1]], [[1, 1]])]), "");
});

test("marksOverlap, this period: duplicate kill cells and kill-and-switch cells, as each filter shows them", () => {
  // 4 kills on 3 cells (two on (1, 1)); 3 switches on 3 cells; (1, 1) and (2, 2) have both.
  const f = events(193, [[1, 1], [1, 1], [2, 2], [7, 7]], [[1, 1], [2, 2], [4, 4]]);
  assert.equal(marksOverlap(193, "now", "both", [f]),
    "t = 193: 4 kills on 3 cells, 3 switches on 3 cells; 2 cells had both and show the kill.");
  assert.equal(marksOverlap(193, "now", "kills", [f]), "t = 193: 4 kills on 3 cells.");
  assert.equal(marksOverlap(193, "now", "switches", [f]), ""); // the switches alone overlap nothing
  const g = events(193, [[1, 1]], [[1, 1], [4, 4]]); // one kill on a switch's cell, no duplicates
  assert.equal(marksOverlap(193, "now", "both", [g]),
    "t = 193: 1 kill on 1 cell, 2 switches on 2 cells; 1 cell had both and show the kill.");
  assert.equal(marksOverlap(193, "now", "kills", [g]), "");
  const big = events(7, Array.from({ length: 1200 }, () => [0, 0]), []);
  assert.equal(marksOverlap(7, "now", "kills", [big]), "t = 7: 1,200 kills on 1 cell.");
});

test("marksOverlap, fading: summed over the periods drawn, with the blending order stated", () => {
  const frames = [events(10, [[1, 1]], [[3, 3]]), events(12, [[1, 1]], [[3, 3]]), events(2, [[9, 9]], [])];
  assert.equal(marksOverlap(12, "fading", "both", frames),
    "t = 10 to 12: 2 kills on 1 cell, 2 switches on 1 cell. Marks on one cell blend in order, oldest first, the kill " +
    "on top within a period."); // t = 2 is too old to be drawn
  assert.equal(marksOverlap(12, "fading", "switches", frames),
    "t = 10 to 12: 2 switches on 1 cell. Marks on one cell blend in order, oldest first, the kill on top within a period.");
  assert.equal(marksOverlap(12, "fading", "both", [events(12, [[1, 1]], [[1, 1]])]),
    "t = 12: 1 kill on 1 cell, 1 switch on 1 cell; 1 cell had both. Marks on one cell blend in order, oldest first, " +
    "the kill on top within a period.");
});

test("a kill and a switch on one cell: the cell is the kill's black", () => {
  const f = fixture();
  f.cellSugar8[5] = 32;
  f.changes.x[0] = 1; // move the fixture's switch onto its kill's cell (1, 1)
  f.changes.y[0] = 1;
  const marks = marksToDraw(f.t, "now", "both", [f]);
  assert.equal(marks.length, 2);
  const image = paintMarks(paintMap(f, "tribe", realLegend), f, marks, realLegend);
  const k = ((f.height - 1 - 1) * f.width + 1) * 4;
  assert.deepEqual(Array.from(image.slice(k, k + 4)), [0, 0, 0, 255]);
});

test("a gold switch mark at opacity 0.5 over a landscape cell: the hand-computed blend", () => {
  const f = fixture(); // cell (1, 0): sugar 8 eighths, spice 2 eighths; no agent there
  f.cellSugar8[5] = 32;
  const before = paintMap(f, "tribe", realLegend);
  const k = ((f.height - 1 - 0) * f.width + 1) * 4;
  // Landscape at s8 = 8, p8 = 2, maxLevel 4: r = 255 - round(20 * 2/32) = 254, g = 255 - round(60 * 2/32) = 251,
  // b = 255 - round(60 * 8/32) - round(45 * 2/32) = 255 - 15 - 3 = 237.
  assert.deepEqual(Array.from(before.slice(k, k + 3)), [254, 251, 237]);
  assert.equal(realLegend.change_colour, "#d4a000"); // (212, 160, 0)
  const after = paintMarks(before, f, [{ kind: "change", x: 1, y: 0, age: 5, opacity: 0.5 }], realLegend);
  // Halfway, rounded half up: (212 + 254) / 2 = 233, (160 + 251) / 2 = 205.5 -> 206, (0 + 237) / 2 = 118.5 -> 119.
  assert.deepEqual(Array.from(after.slice(k, k + 4)), [233, 206, 119, 255]);
});

test("a fading mark is blended over its cell at its opacity, and only there", () => {
  const f = fixture();
  f.cellSugar8[5] = 32;
  const marks = [{ kind: "kill", x: 1, y: 0, age: 5, opacity: markOpacity(5) }]; // an empty cell
  const before = paintMap(f, "tribe", realLegend);
  const after = paintMarks(paintMap(f, "tribe", realLegend), f, marks, realLegend);
  const k = ((f.height - 1 - 0) * f.width + 1) * 4;
  const base = Array.from(before.slice(k, k + 3));
  assert.deepEqual(Array.from(after.slice(k, k + 3)), base.map((c) => Math.floor(0.5 * c + 0.5)));
  for (let j = 0; j < before.length; j++) if (j < k || j >= k + 4) assert.equal(after[j], before[j]);
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
  assert.deepEqual(hit.cell, { x: 1, y: 0, sugar: 1, spice: 0.25, pollutionBand: 8 });
  assert.deepEqual(hitTest(f, 2, 1).cell, { x: 2, y: 1, sugar: 255 / 8, spice: 6 / 8, pollutionBand: 2 });
  assert.equal(hitTest(f, 3, 0), null);
  assert.equal(hitTest(f, 0, -1), null);
});

const range = (a, b) => Array.from({ length: b - a + 1 }, (_, i) => a + i);

test("missingMarkPeriods: the periods of the 9 before the shown one whose frames the page does not have", () => {
  assert.deepEqual(missingMarkPeriods(20, 0, range(11, 20)), []);
  assert.deepEqual(missingMarkPeriods(20, 0, new Set(range(11, 19))), []); // the shown frame itself is not a mark frame
  assert.deepEqual(missingMarkPeriods(20, 15, range(15, 20)), [11, 12, 13, 14]); // no longer kept
  assert.deepEqual(missingMarkPeriods(20, 0, [11, 12, 14, 15, 17, 18, 19, 20]), [13, 16]); // failed or 404
  assert.deepEqual(missingMarkPeriods(5, 0, range(0, 5)), []); // no period before 0 exists, so none is missing
  assert.deepEqual(missingMarkPeriods(3, 0, [0, 2, 3]), [1]);
  assert.deepEqual(missingMarkPeriods(0, 0, [0]), []);
});

test("marksNote: says which marks are missing and why, and nothing when all 10 periods' marks are drawn", () => {
  assert.equal(marksNote(20, 0, range(11, 20)), "");
  assert.equal(marksNote(20, 15, range(15, 20)),
    "Marks before t = 15 are not available (no longer kept), so fewer marks are drawn than the model made.");
  assert.equal(marksNote(20, 0, [11, 12, 14, 15, 17, 18, 19, 20], [13, 16]),
    "Marks of t = 13, 16 could not be loaded, so fewer marks are drawn than the model made.");
  assert.equal(marksNote(20, 15, [15, 17, 18, 19, 20], [16]),
    "Marks before t = 15 are not available (no longer kept). Marks of t = 16 could not be loaded, so fewer marks " +
    "are drawn than the model made.");
});

// The legend the server sends, written by julia/test/test_xxl_viewer_frame.jl ("frame legend") from the default
// experiment's run model.
const realLegend = JSON.parse(readFileSync(new URL("fixture-legend.json", here), "utf8"));
const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const lin = (c) => ((c /= 255) <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const luminance = (h) => rgb(h).map(lin).reduce((s, c, i) => s + c * [0.2126, 0.7152, 0.0722][i], 0);

test("every agent colour of every palette stands out on every landscape colour (RGB distance >= 60)", () => {
  const top = 8 * realLegend.max_level;
  const cells = [];
  for (let s = 0; s <= top; s++) for (let p = 0; p <= top; p++) cells.push(landscapeColour(s, p, realLegend.max_level));
  for (const mode of realLegend.modes) {
    for (const colour of realLegend.palettes[mode]) {
      const c = rgb(colour);
      const nearest = Math.min(...cells.map((l) => Math.hypot(c[0] - l[0], c[1] - l[1], c[2] - l[2])));
      assert.ok(nearest >= 60, `${mode} ${colour} is ${nearest.toFixed(1)} from a landscape colour`);
    }
  }
});

test("every agent colour of every palette is told apart from both mark colours (RGB distance >= 60)", () => {
  // A one-cell mark replaces its cell's colour, so a mark in an agent's colour would read as an agent (or the reverse).
  const marks = { kill: rgb(realLegend.kill_colour), change: rgb(realLegend.change_colour) };
  for (const mode of realLegend.modes) {
    for (const colour of realLegend.palettes[mode]) {
      const c = rgb(colour);
      for (const [kind, m] of Object.entries(marks)) {
        const dist = Math.hypot(c[0] - m[0], c[1] - m[1], c[2] - m[2]);
        assert.ok(dist >= 60, `${mode} ${colour} is ${dist.toFixed(1)} from the ${kind} mark colour`);
      }
    }
  }
});

test("the culture shade runs from the tribe blue to the tribe red, no step lighter than its ends", () => {
  const p = realLegend.palettes.culture;
  assert.equal(p.length, realLegend.ntags + 1);
  assert.equal(p[0], realLegend.palettes.tribe[0]);
  assert.equal(p[p.length - 1], realLegend.palettes.tribe[1]);
  const ends = Math.max(luminance(p[0]), luminance(p[p.length - 1]));
  for (const c of p) assert.ok(luminance(c) <= ends + 1e-9, `${c} is lighter than the ends`);
});

test("wealth bands and disease steps darken from low to high", () => {
  const darkening = (list) => list.every((c, i) => i === 0 || luminance(c) < luminance(list[i - 1]));
  assert.ok(darkening(realLegend.palettes.wealth), realLegend.palettes.wealth.join(" "));
  assert.ok(darkening(realLegend.palettes.disease.slice(1)), realLegend.palettes.disease.join(" ")); // step 0: neutral
});

// The pollution palette the server sends, read from julia/viewer/encoding.jl's POLLUTION_PALETTE (the legend fixture is
// the default experiment's, which has no pollution), and a legend with the pollution entry `pollution_legend` gives.
const encoding = readFileSync(new URL("../../viewer/encoding.jl", here), "utf8");
const POLLUTION_PALETTE = encoding.match(/const POLLUTION_PALETTE = \[([^\]]*)\]/)[1].match(/#[0-9a-f]{6}/g);
const pollutionLegend = {
  ...realLegend,
  pollution: {
    palette: POLLUTION_PALETTE,
    labels: ["0 (clean)", "below 1", "1 to < 3", "3 to < 10", "10 to < 30", "30 to < 100", "100 to < 300",
      "300 to < 1000", "1000 or more"],
    edges: [1, 3, 10, 30, 100, 300, 1000], start: 350, diffusion_start: 450, rich_cut: 5, rich_share: 0.32,
  },
};

const pixelOf = (image, f, x, y) => {
  const k = ((f.height - 1 - y) * f.width + x) * 4;
  return Array.from(image.slice(k, k + 4));
};

test("the ground menu: resources (the default) or pollution, pollution only for a run that has it", () => {
  assert.deepEqual(GROUNDS, [{ value: "resources", label: "resources" }, { value: "pollution", label: "pollution" }]);
  assert.deepEqual(groundsFor(pollutionLegend), GROUNDS);
  assert.deepEqual(groundsFor(realLegend), [GROUNDS[0]]);
  assert.deepEqual(groundsFor(null), [GROUNDS[0]]);
});

test("groundFor: a run without pollution falls back to resources whatever was chosen", () => {
  assert.equal(groundFor(pollutionLegend, "pollution"), "pollution");
  assert.equal(groundFor(pollutionLegend, "resources"), "resources");
  assert.equal(groundFor(realLegend, "pollution"), "resources");
  assert.equal(groundFor(null, "pollution"), "resources");
  assert.equal(groundFor(pollutionLegend, undefined), "resources");
});

test("paintMap with the pollution ground: each empty cell is its band's colour, the agents on top", () => {
  const f = fixture(); // bands [0, 8, 1, 4, 7, 2]; agents at (2, 0) (cell 2) and (0, 1) (cell 3)
  const palette = pollutionLegend.pollution.palette;
  const image = paintMap(f, "tribe", pollutionLegend, "pollution");
  assert.equal(image.length, 3 * 2 * 4);
  assert.deepEqual(pixelOf(image, f, 0, 0), [...rgb(palette[0]), 255]);
  assert.deepEqual(pixelOf(image, f, 1, 0), [...rgb(palette[8]), 255]);
  assert.deepEqual(pixelOf(image, f, 1, 1), [...rgb(palette[7]), 255]);
  assert.deepEqual(pixelOf(image, f, 2, 1), [...rgb(palette[2]), 255]);
  assert.deepEqual(pixelOf(image, f, 0, 1), [0x25, 0x63, 0xeb, 255]); // agent 0, blue, on band 4
  assert.deepEqual(pixelOf(image, f, 2, 0), [0xc0, 0x39, 0x2b, 255]); // agent 1, red, on band 1
  // The resource levels play no part: the fixture's 255 eighths, above the landscape's capacity, does not throw here.
  assert.throws(() => paintMap(f, "tribe", pollutionLegend, "resources"), RangeError);
});

test("pollution bands: band 0 is white, band 1 (any pollution at all) is not, band 8 is the last colour", () => {
  const f = fixture();
  const palette = pollutionLegend.pollution.palette;
  assert.equal(palette.length, 9);
  assert.equal(palette[0], "#ffffff");
  assert.notEqual(palette[1], "#ffffff");
  f.cellPollution[0] = 1;
  const image = paintMap(f, "tribe", pollutionLegend, "pollution");
  assert.deepEqual(pixelOf(image, f, 0, 0), [...rgb(palette[1]), 255]);
  assert.notDeepEqual(pixelOf(image, f, 0, 0), [255, 255, 255, 255]);
  f.cellPollution[0] = 0;
  assert.deepEqual(pixelOf(paintMap(f, "tribe", pollutionLegend, "pollution"), f, 0, 0), [255, 255, 255, 255]);
  f.cellPollution[0] = 8;
  assert.deepEqual(pixelOf(paintMap(f, "tribe", pollutionLegend, "pollution"), f, 0, 0),
    [...rgb(palette[palette.length - 1]), 255]);
});

test("paintMap with the pollution ground throws for a legend without pollution or a band without a colour", () => {
  const f = fixture();
  assert.throws(() => paintMap(f, "tribe", realLegend, "pollution"), /no pollution/);
  f.cellPollution[0] = 9;
  assert.throws(() => paintMap(f, "tribe", pollutionLegend, "pollution"), /pollution band 9 has no colour/);
  assert.throws(() => paintMap(fixture(), "tribe", pollutionLegend, "rubble"), /no ground/);
});

test("paintMap's ground is resources by default and when asked, whatever the legend's pollution", () => {
  const f = fixture();
  f.cellSugar8[5] = 32;
  const plain = paintMap(f, "tribe", realLegend);
  assert.deepEqual(paintMap(f, "tribe", realLegend, "resources"), plain);
  assert.deepEqual(paintMap(f, "tribe", pollutionLegend), plain);
});

test("marks are drawn over the pollution ground as over the landscape", () => {
  const f = fixture();
  const marks = marksToDraw(f.t, "now", "both", [f]);
  const image = paintMarks(paintMap(f, "tribe", pollutionLegend, "pollution"), f, marks, pollutionLegend);
  assert.deepEqual(pixelOf(image, f, 1, 1), [...rgb(pollutionLegend.kill_colour), 255]);
  assert.deepEqual(pixelOf(image, f, 2, 0), [...rgb(pollutionLegend.change_colour), 255]);
});

test("every agent colour of every palette stands out on every pollution colour (RGB distance >= 60)", () => {
  const ground = pollutionLegend.pollution.palette.map(rgb);
  for (const mode of pollutionLegend.modes) {
    for (const colour of pollutionLegend.palettes[mode]) {
      const c = rgb(colour);
      const nearest = Math.min(...ground.map((l) => Math.hypot(c[0] - l[0], c[1] - l[1], c[2] - l[2])));
      assert.ok(nearest >= 60, `${mode} ${colour} is ${nearest.toFixed(1)} from a pollution colour`);
    }
  }
});

test("both mark colours stand out on every pollution colour (RGB distance >= 60)", () => {
  const marks = { kill: rgb(pollutionLegend.kill_colour), change: rgb(pollutionLegend.change_colour) };
  for (const g of pollutionLegend.pollution.palette) {
    const l = rgb(g);
    for (const [kind, m] of Object.entries(marks)) {
      const dist = Math.hypot(m[0] - l[0], m[1] - l[1], m[2] - l[2]);
      assert.ok(dist >= 60, `the ${kind} mark colour is ${dist.toFixed(1)} from the pollution colour ${g}`);
    }
  }
});

test("hitTest gives each cell's pollution band, over an agent and over an empty cell", () => {
  const f = fixture();
  assert.equal(hitTest(f, 0, 0).cell.pollutionBand, 0);
  assert.equal(hitTest(f, 1, 0).cell.pollutionBand, 8);
  assert.equal(hitTest(f, 2, 0).cell.pollutionBand, 1); // agent 1's cell
  assert.equal(hitTest(f, 0, 1).cell.pollutionBand, 4); // agent 0's cell
});
