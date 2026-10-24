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

// Cell color for sugar level s and spice level p, each scaled by its run's highest capacity (0 max: no term).
// Linear in s and p, so different (s, p) pairs never share a color before rounding; rounded half up.
export function cellColor(s, p, smax, pmax) {
  const fs = smax > 0 ? (WEIGHT * s) / smax : 0;
  const fp = pmax > 0 ? (WEIGHT * p) / pmax : 0;
  return WHITE.map((w, i) => Math.floor(w + fs * (YELLOW[i] - w) + fp * (RUST[i] - w) + 0.5));
}

function levels(max) {
  return Array.from({ length: Math.max(0, max) + 1 }, (_, i) => i);
}

// Legend swatches: whole levels 0..max of each resource, colored by cellColor itself.
export function legendCells(smax, pmax) {
  const sugar = levels(smax);
  const spice = levels(pmax);
  return { sugar, spice, colors: sugar.map((s) => spice.map((p) => cellColor(s, p, smax, pmax))) };
}

export function wealth(agent) {
  return agent.sugar + agent.spice;
}

export function bandOf(w) {
  let band = 0;
  while (band < BANDS.length && w >= BANDS[band]) band++;
  return band;
}

// Agent color by attribute. Adding an attribute later means adding a key.
export const COLOR_MODES = {
  tribe: {
    label: "tribe",
    available: (info) => Boolean(info.tribes),
    color: (agent) => TRIBE_COLORS[agent.tribe] ?? NEUTRAL,
    legend: () => [
      { label: "red tribe", color: TRIBE_COLORS.red },
      { label: "blue tribe", color: TRIBE_COLORS.blue },
    ],
  },
  wealth: {
    label: "wealth (sugar + spice)",
    available: () => true,
    color: (agent) => BAND_COLORS[bandOf(wealth(agent))],
    legend: () => BAND_LABELS.map((label, i) => ({ label, color: BAND_COLORS[i] })),
  },
  none: {
    label: "none",
    available: () => true,
    color: () => NEUTRAL,
    legend: () => [{ label: "every agent", color: NEUTRAL }],
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
