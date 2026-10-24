// Every visual encoding the viewer uses, as fixed functions of model values (viewer design, "Anti-goal").
// Nothing here rescales per frame. The board, the legend and the tests all call these same functions.
// No DOM access, so Node can import this module for tests/js/encoding.test.mjs.

export const WHITE = [255, 255, 255];
export const YELLOW = [232, 190, 40]; // sugar
export const RUST = [176, 80, 40]; // spice
// Weight of each resource at its run's highest capacity. With 0.58 no channel clips, and all 33 x 33 levels in
// eighths from 0 to 4 draw as distinct integer colors (tested).
export const WEIGHT = 0.58;

export const BANDS = [10, 30, 100, 300]; // wealth band lower bounds after the first; lower bounds inclusive
export const BAND_LABELS = ["< 10", "10–30", "30–100", "100–300", "≥ 300"];
export const BAND_COLORS = ["#fde0c5", "#f9a66c", "#e8603c", "#b22b28", "#5c0f1e"]; // light to dark
export const BAND_RADII = [0.2, 0.28, 0.36, 0.44, 0.52]; // fraction of a cell
export const TRIBE_COLORS = { red: "#d62728", blue: "#1f5fbf" }; // as the book colors the tribes
export const NEUTRAL = "#333333";
// Thin dark ring around every agent dot, so the palest band stays visible on pale cells (contrast >= 3 on every
// cell color, tested). It marks presence only; color and size carry the attribute.
export const OUTLINE = "#1d1d1f";
export const OUTLINE_WIDTH = 0.06; // fraction of a cell, at least one device pixel
const UNIFORM_RADIUS = 0.4;

// xl runs (500 x 500) draw each cell as about one pixel, with each agent filling its cell: no room for the outline.
// So xl has its own palettes: a paler landscape (the same blend at XL_WEIGHT, the smallest weight tried at which all
// 33 x 33 eighths still draw distinctly) and agent colors with contrast >= 3 against every xl cell (3.26 at worst,
// tested). The bands still darken with wealth; the tribes stay red and blue, as the book colors them.
export const XL_WEIGHT = 0.3;
export const PALETTES = {
  regular: { weight: WEIGHT, tribe: TRIBE_COLORS, neutral: NEUTRAL, bands: BAND_COLORS },
  xl: {
    weight: XL_WEIGHT,
    tribe: { red: "#b71c1c", blue: "#1f5fbf" },
    neutral: "#333333",
    bands: ["#b23a0c", "#a01036", "#6d1a7a", "#3a0c6b", "#0a0612"],
  },
};

// Cell color for sugar level s and spice level p, each scaled by its run's highest capacity (0 max: no term).
// Linear in s and p, so different (s, p) pairs never share a color before rounding; rounded half up.
// `weight` is WEIGHT, or XL_WEIGHT on xl runs.
export function cellColor(s, p, smax, pmax, weight = WEIGHT) {
  const fs = smax > 0 ? (weight * s) / smax : 0;
  const fp = pmax > 0 ? (weight * p) / pmax : 0;
  return WHITE.map((w, i) => Math.floor(w + fs * (YELLOW[i] - w) + fp * (RUST[i] - w) + 0.5));
}

function levels(max) {
  return Array.from({ length: Math.max(0, max) + 1 }, (_, i) => i);
}

// Legend swatches: whole levels 0..max of each resource, colored by cellColor itself.
export function legendCells(smax, pmax, weight = WEIGHT) {
  const sugar = levels(smax);
  const spice = levels(pmax);
  return { sugar, spice, colors: sugar.map((s) => spice.map((p) => cellColor(s, p, smax, pmax, weight))) };
}

export function wealth(agent) {
  return agent.sugar + agent.spice;
}

export function bandOf(w) {
  let band = 0;
  while (band < BANDS.length && w >= BANDS[band]) band++;
  return band;
}

// Wealth for display: two decimals, or as many more as it takes for the number shown to fall in the same band
// as the value (9.996 shows as "9.996", never "10.00" beside a "< 10" band). Whole numbers show as they are.
export function formatWealth(w) {
  if (Number.isInteger(w)) return String(w);
  for (let digits = 2; digits <= 17; digits++) {
    const shown = w.toFixed(digits);
    if (bandOf(Number(shown)) === bandOf(w)) return shown;
  }
  return String(w); // shortest exact form
}

// Agent color by attribute, from a palette (PALETTES.regular unless given). Adding an attribute means adding a key.
export const COLOR_MODES = {
  tribe: {
    label: "tribe",
    available: (info) => Boolean(info.tribes),
    color: (agent, palette = PALETTES.regular) => palette.tribe[agent.tribe] ?? palette.neutral,
    legend: (palette = PALETTES.regular) => [
      { label: "red tribe", color: palette.tribe.red },
      { label: "blue tribe", color: palette.tribe.blue },
    ],
  },
  wealth: {
    label: "wealth (sugar + spice)",
    available: () => true,
    color: (agent, palette = PALETTES.regular) => palette.bands[bandOf(wealth(agent))],
    legend: (palette = PALETTES.regular) => BAND_LABELS.map((label, i) => ({ label, color: palette.bands[i] })),
  },
  none: {
    label: "none",
    available: () => true,
    color: (agent, palette = PALETTES.regular) => palette.neutral,
    legend: (palette = PALETTES.regular) => [{ label: "every agent", color: palette.neutral }],
  },
};

// Agent dot radius, as a fraction of a cell, by attribute.
export const SIZE_MODES = {
  wealth: {
    label: "wealth (sugar + spice)",
    radius: (agent) => BAND_RADII[bandOf(wealth(agent))],
    legend: () => BAND_LABELS.map((label, i) => ({ label, radius: BAND_RADII[i] })),
  },
  none: {
    label: "none",
    radius: () => UNIFORM_RADIUS,
    legend: () => [{ label: "every agent", radius: UNIFORM_RADIUS }],
  },
};
