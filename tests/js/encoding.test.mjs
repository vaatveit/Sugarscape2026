import { test } from "node:test";
import assert from "node:assert/strict";

import {
  BANDS, BAND_COLORS, BAND_LABELS, BAND_RADII, COLOR_MODES, NEUTRAL, SIZE_MODES, TRIBE_COLORS,
  OUTLINE, bandOf, cellColor, legendCells, wealth,
} from "../../viewer/static/encoding.mjs";

const LOWER = [0, ...BANDS]; // each band's lower bound

test("blend never clips and draws 33x33 eighths distinctly", () => {
  const seen = new Set();
  for (let i = 0; i <= 32; i++) {
    for (let j = 0; j <= 32; j++) {
      const rgb = cellColor(i / 8, j / 8, 4, 4);
      assert.equal(rgb.length, 3);
      for (const c of rgb) assert.ok(Number.isInteger(c) && c >= 0 && c <= 255, `${i},${j}: ${rgb}`);
      seen.add(rgb.join());
    }
  }
  assert.equal(seen.size, 33 * 33);
});

test("zero levels are white; sugar-only runs have no spice term", () => {
  assert.deepEqual(cellColor(0, 0, 4, 4), [255, 255, 255]);
  const sugarOnly = cellColor(2, 0, 4, 0);
  assert.deepEqual(sugarOnly, cellColor(2, 0, 4, 4));
  assert.ok(sugarOnly.every(Number.isFinite));
});

test("blend increases monotonically in each resource", () => {
  const sum = (rgb) => rgb[0] + rgb[1] + rgb[2];
  for (let k = 0; k <= 32; k++) {
    for (let i = 0; i < 32; i++) {
      assert.ok(sum(cellColor((i + 1) / 8, k / 8, 4, 4)) < sum(cellColor(i / 8, k / 8, 4, 4)), `sugar ${i}, spice ${k}`);
      assert.ok(sum(cellColor(k / 8, (i + 1) / 8, 4, 4)) < sum(cellColor(k / 8, i / 8, 4, 4)), `spice ${i}, sugar ${k}`);
    }
  }
});

test("band boundaries", () => {
  const cases = [[0, 0], [9.99, 0], [10, 1], [29.99, 1], [30, 2], [99.99, 2], [100, 3], [299.99, 3], [300, 4], [1e6, 4]];
  for (const [w, band] of cases) assert.equal(bandOf(w), band, `wealth ${w}`);
  assert.equal(BAND_LABELS.length, 5);
});

test("wealth is sugar plus spice", () => {
  const a = { sugar: 3.5, spice: 6.5 };
  assert.equal(wealth(a), 10);
  assert.equal(bandOf(wealth(a)), 1);
});

test("band sizes strictly increase; band colors are distinct", () => {
  assert.equal(BAND_RADII.length, 5);
  for (let i = 1; i < 5; i++) assert.ok(BAND_RADII[i] > BAND_RADII[i - 1]);
  assert.equal(new Set(BAND_COLORS).size, 5);
  assert.ok(!BAND_COLORS.includes(NEUTRAL));
});

test("legend is built from the board's own functions", () => {
  const cells = legendCells(4, 4);
  assert.deepEqual(cells.sugar, [0, 1, 2, 3, 4]);
  assert.deepEqual(cells.spice, [0, 1, 2, 3, 4]);
  for (let i = 0; i <= 4; i++) for (let j = 0; j <= 4; j++) assert.deepEqual(cells.colors[i][j], cellColor(i, j, 4, 4));
  const sugarOnly = legendCells(4, 0);
  assert.deepEqual(sugarOnly.spice, [0]);
  assert.deepEqual(sugarOnly.colors.map((row) => row[0]), [0, 1, 2, 3, 4].map((s) => cellColor(s, 0, 4, 0)));

  const colors = COLOR_MODES.wealth.legend();
  const radii = SIZE_MODES.wealth.legend();
  assert.equal(colors.length, 5);
  assert.equal(radii.length, 5);
  LOWER.forEach((lo, i) => {
    assert.equal(colors[i].color, COLOR_MODES.wealth.color({ sugar: lo, spice: 0 }));
    assert.equal(radii[i].radius, SIZE_MODES.wealth.radius({ sugar: lo, spice: 0 }));
    assert.equal(colors[i].label, BAND_LABELS[i]);
  });
  assert.deepEqual(COLOR_MODES.tribe.legend().map((e) => e.color), [TRIBE_COLORS.red, TRIBE_COLORS.blue]);
  assert.equal(SIZE_MODES.none.legend()[0].radius, SIZE_MODES.none.radius({ sugar: 500, spice: 0 }));
});

test("tribe mode only where tribes exist", () => {
  assert.equal(COLOR_MODES.tribe.available({ tribes: false }), false);
  assert.equal(COLOR_MODES.tribe.available({ tribes: true }), true);
  assert.ok(COLOR_MODES.wealth.available({ tribes: false }) && COLOR_MODES.none.available({ tribes: false }));
  assert.equal(COLOR_MODES.tribe.color({ tribe: "red" }), TRIBE_COLORS.red);
  assert.equal(COLOR_MODES.tribe.color({ tribe: "blue" }), TRIBE_COLORS.blue);
  assert.equal(COLOR_MODES.none.color({ tribe: "red", sugar: 400, spice: 0 }), NEUTRAL);
  assert.equal(SIZE_MODES.none.radius({ sugar: 0, spice: 0 }), 0.4);
});

// WCAG relative luminance and contrast ratio.
function luminance(rgb) {
  const lin = rgb.map((c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
}
const contrast = (a, b) => { const [x, y] = [luminance(a), luminance(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
const hexRgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));

test("every agent's outline stands out from every cell color", () => {
  // The lightest wealth band is pale on pale cells; the outline keeps every agent visible (final review #8).
  for (let i = 0; i <= 32; i++) {
    for (let j = 0; j <= 32; j++) {
      const c = contrast(hexRgb(OUTLINE), cellColor(i / 8, j / 8, 4, 4));
      assert.ok(c >= 3, `outline vs cell ${i / 8},${j / 8}: ${c.toFixed(2)}`);
    }
  }
});
