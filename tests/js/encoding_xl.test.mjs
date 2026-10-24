import { test } from "node:test";
import assert from "node:assert/strict";

import {
  BAND_COLORS, COLOR_MODES, NEUTRAL, PALETTES, TRIBE_COLORS, WEIGHT, XL_WEIGHT, cellColor,
} from "../../viewer/static/encoding.mjs";

// As in encoding.test.mjs (WCAG relative luminance and contrast).
function luminance(rgb) {
  const lin = rgb.map((c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
}
const contrast = (a, b) => { const [x, y] = [luminance(a), luminance(b)].sort((m, n) => n - m); return (x + 0.05) / (y + 0.05); };
const hexRgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));

// CIELAB (D65) and the CIE76 color difference.
const lin = (c) => { c /= 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
function lab(rgb) {
  const [r, g, b] = rgb.map(lin);
  const f = (t) => (t > 216 / 24389 ? Math.cbrt(t) : (24389 / 27 * t + 16) / 116);
  const x = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047), y = f(0.2126 * r + 0.7152 * g + 0.0722 * b);
  const z = f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883);
  return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
}
const deltaE = (a, b) => Math.hypot(...lab(a).map((v, i) => v - lab(b)[i]));
const eighths = () => Array.from({ length: 33 * 33 }, (_, n) => [Math.floor(n / 33) / 8, (n % 33) / 8]);
const xlCells = () => eighths().map(([s, p]) => cellColor(s, p, 4, 4, XL_WEIGHT));

function hue(rgb) {
  const [r, g, b] = rgb.map((c) => c / 255);
  const max = Math.max(r, g, b), d = max - Math.min(r, g, b);
  if (d === 0) return 0;
  const h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return (h * 60 + 360) % 360;
}

const xlAgentColors = () => [PALETTES.xl.tribe.red, PALETTES.xl.tribe.blue, PALETTES.xl.neutral, ...PALETTES.xl.bands];

test("xl blend never clips and draws 33x33 eighths distinctly", () => {
  const cells = xlCells();
  for (const rgb of cells) for (const c of rgb) assert.ok(Number.isInteger(c) && c >= 0 && c <= 255, String(rgb));
  assert.equal(new Set(cells.map(String)).size, 33 * 33);
});

test("xl cells are paler than regular cells", () => {
  const sum = (rgb) => rgb[0] + rgb[1] + rgb[2];
  assert.ok(XL_WEIGHT < WEIGHT);
  for (const [s, p] of eighths()) assert.ok(sum(cellColor(s, p, 4, 4, XL_WEIGHT)) >= sum(cellColor(s, p, 4, 4)), `${s},${p}`);
});

test("every xl agent color has 3:1 contrast against every xl cell", () => {
  // One pixel per cell leaves no room for the regular outline, so the fill itself must stand out.
  const cells = xlCells();
  for (const color of xlAgentColors()) {
    const worst = Math.min(...cells.map((cell) => contrast(hexRgb(color), cell)));
    assert.ok(worst >= 3, `${color}: ${worst.toFixed(2)}`);
  }
});

test("xl bands darken in order and stay apart", () => {
  const bands = PALETTES.xl.bands.map(hexRgb);
  assert.equal(bands.length, 5);
  for (let i = 1; i < bands.length; i++) {
    assert.ok(lab(bands[i])[0] < lab(bands[i - 1])[0], `L* of band ${i}`);
    assert.ok(deltaE(bands[i], bands[i - 1]) >= 15, `bands ${i - 1},${i}: ${deltaE(bands[i], bands[i - 1]).toFixed(1)}`);
  }
});

test("xl tribes keep the book's hues", () => {
  const red = hue(hexRgb(PALETTES.xl.tribe.red));
  const blue = hue(hexRgb(PALETTES.xl.tribe.blue));
  assert.ok(red <= 15 || red >= 345, `red hue ${red}`);
  assert.ok(blue >= 200 && blue <= 240, `blue hue ${blue}`);
});

test("the regular palette is today's", () => {
  assert.deepEqual(PALETTES.regular, { weight: WEIGHT, tribe: TRIBE_COLORS, neutral: NEUTRAL, bands: BAND_COLORS });
  assert.equal(COLOR_MODES.tribe.color({ tribe: "red" }), TRIBE_COLORS.red);
  assert.equal(COLOR_MODES.wealth.color({ sugar: 50, spice: 0 }), BAND_COLORS[2]);
});

test("modes use the palette they're given", () => {
  const xl = PALETTES.xl;
  assert.equal(COLOR_MODES.wealth.color({ sugar: 50, spice: 0 }, xl), xl.bands[2]);
  assert.equal(COLOR_MODES.tribe.color({ tribe: "blue" }, xl), xl.tribe.blue);
  assert.equal(COLOR_MODES.tribe.color({ tribe: null }, xl), xl.neutral);
  assert.equal(COLOR_MODES.none.color({}, xl), xl.neutral);
  assert.deepEqual(COLOR_MODES.wealth.legend(xl).map((e) => e.color), xl.bands);
  assert.deepEqual(COLOR_MODES.tribe.legend(xl).map((e) => e.color), [xl.tribe.red, xl.tribe.blue]);
  assert.deepEqual(COLOR_MODES.none.legend(xl).map((e) => e.color), [xl.neutral]);
});
