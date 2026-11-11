// The map: every encoding it draws, as fixed functions of a frame's values and the run's legend (julia/viewer/encoding.jl),
// and the drawing itself. Nothing here rescales with the frame: the same values give the same look at every period.
// Only drawMap touches a canvas, so Node can import this module for julia/test/js/map.test.mjs.

/** The frame column holding each colour mode's code; the palette entry of that code is the agent's colour. */
export const MODE_FIELDS = { tribe: "tribe", culture: "ones", wealth: "wealth", disease: "disease", credit: "role" };

/** Marks stay for this many periods (the legend's `mark_periods`), fading linearly. */
export const MARK_PERIODS = 10;

// The landscape blend: how far each channel falls from white at a resource's full capacity. Green carries spice alone
// and blue carries sugar (with a fixed share of spice), so with at least one step of a channel per eighth of a level,
// each (sugar, spice) pair has its own colour. Every channel stays at 150 or above, so the agents read first.
const SPICE_DROP = { r: 20, g: 60, b: 45 };
const SUGAR_DROP_B = 60;
/** The largest landscape capacity, in eighths, that the blend draws one-to-one (one channel step per eighth). */
export const MAX_EIGHTHS = 60;

/**
 * landscapeColour(s8, p8, maxLevel) -> [r, g, b]: the cell colour for sugar s8 / 8 and spice p8 / 8, scaled by the
 * landscape's largest capacity `maxLevel` (fixed for the run, never the frame's largest level). One-to-one over all s8, p8
 * in 0..8 * maxLevel while 8 * maxLevel <= MAX_EIGHTHS; empty cells are white. A level it cannot draw exactly throws.
 */
export function landscapeColour(s8, p8, maxLevel) {
  const top = 8 * maxLevel;
  if (!Number.isInteger(top) || top < 0 || top > MAX_EIGHTHS) {
    throw new RangeError(`a landscape capacity of ${maxLevel} cannot be drawn one-to-one (at most ${MAX_EIGHTHS / 8})`);
  }
  for (const v of [s8, p8]) {
    if (!Number.isInteger(v) || v < 0 || v > top) {
      throw new RangeError(`a level of ${v} eighths is outside 0 to ${top} (the landscape's capacity)`);
    }
  }
  const fs = top === 0 ? 0 : s8 / top;
  const fp = top === 0 ? 0 : p8 / top;
  return [
    255 - Math.round(SPICE_DROP.r * fp),
    255 - Math.round(SPICE_DROP.g * fp),
    255 - Math.round(SUGAR_DROP_B * fs) - Math.round(SPICE_DROP.b * fp),
  ];
}

/** agentColour(frame, i, mode, legend) -> "#rrggbb": the palette entry of agent i's code for `mode`. */
export function agentColour(frame, i, mode, legend) {
  const field = MODE_FIELDS[mode];
  if (field === undefined) throw new Error(`no colour mode ${JSON.stringify(mode)}`);
  const colour = legend.palettes[mode][frame.agents[field][i]];
  if (colour === undefined) throw new Error(`${mode} code ${frame.agents[field][i]} has no colour in the legend`);
  return colour;
}

/** markOpacity(age): 1 - age / 10 for a mark 0 to 9 periods old (0 = the period shown), else 0. */
export function markOpacity(age) {
  return age >= 0 && age < MARK_PERIODS ? 1 - age / MARK_PERIODS : 0;
}

/**
 * markList(frame, recentFrames) -> [{kind: "kill" | "change", x, y, age, opacity}]: the kills and tribe changes of every
 * frame among `frame` and `recentFrames` from the last 10 periods up to the one shown, oldest first (so the newest are
 * drawn on top). A frame given twice counts once; a period that is not given (no longer kept) adds nothing.
 */
export function markList(frame, recentFrames) {
  const byT = new Map();
  for (const f of [frame, ...recentFrames]) if (f && !byT.has(f.t)) byT.set(f.t, f);
  const marks = [];
  for (const f of [...byT.values()].sort((a, b) => a.t - b.t)) {
    const age = frame.t - f.t;
    const opacity = markOpacity(age);
    if (opacity <= 0) continue;
    for (let i = 0; i < f.kills.x.length; i++) marks.push({ kind: "kill", x: f.kills.x[i], y: f.kills.y[i], age, opacity });
    for (let i = 0; i < f.changes.x.length; i++) {
      marks.push({ kind: "change", x: f.changes.x[i], y: f.changes.y[i], age, opacity });
    }
  }
  return marks;
}

/**
 * missingMarkPeriods(t, oldestKept, obtained) -> the periods among the 9 before t (none before period 0) whose frames are
 * not among `obtained` (an iterable of periods): their marks are not drawn.
 */
export function missingMarkPeriods(t, oldestKept, obtained) {
  const have = new Set(obtained);
  const missing = [];
  for (let u = Math.max(0, t - (MARK_PERIODS - 1)); u < t; u++) if (!have.has(u)) missing.push(u);
  return missing;
}

/**
 * marksNote(t, oldestKept, obtained, failed = []) -> "" when the marks of all 10 periods up to t are drawn, else what is
 * missing: the periods no longer kept (or not found), and those whose frames failed to load (`failed`, listed).
 */
export function marksNote(t, oldestKept, obtained, failed = []) {
  const missing = missingMarkPeriods(t, oldestKept, obtained);
  if (missing.length === 0) return "";
  const broken = new Set(failed);
  const lost = missing.filter((u) => !broken.has(u));
  const bad = missing.filter((u) => broken.has(u));
  const parts = [];
  if (lost.length) parts.push(`Marks before t = ${lost[lost.length - 1] + 1} are not available (no longer kept)`);
  if (bad.length) parts.push(`Marks of t = ${bad.join(", ")} could not be loaded`);
  return `${parts.join(". ")}, so fewer crosses and rings are drawn than the model made.`;
}

function rgbOf(hex) {
  return [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
}

/**
 * paintMap(frame, mode, legend) -> Uint8ClampedArray: RGBA, one pixel per cell, north (the largest y) at the top. Each
 * cell is its landscape colour; a cell with an agent is the agent's colour for `mode`. Nothing is blended.
 */
export function paintMap(frame, mode, legend) {
  const { width: W, height: H } = frame;
  const top = 8 * legend.max_level;
  const lut = new Uint8Array((top + 1) * (top + 1) * 3); // (s8, p8) -> rgb, each pair computed once
  for (let s = 0; s <= top; s++) {
    for (let p = 0; p <= top; p++) lut.set(landscapeColour(s, p, legend.max_level), (s * (top + 1) + p) * 3);
  }
  const image = new Uint8ClampedArray(W * H * 4);
  const { cellSugar8: cs, cellSpice8: cp } = frame;
  for (let y = 0; y < H; y++) {
    const row = (H - 1 - y) * W;
    for (let x = 0; x < W; x++) {
      const c = y * W + x;
      const s = cs[c], p = cp[c];
      if (s > top || p > top) landscapeColour(s, p, legend.max_level); // throws: a level the blend cannot show
      const l = (s * (top + 1) + p) * 3;
      const k = (row + x) * 4;
      image[k] = lut[l];
      image[k + 1] = lut[l + 1];
      image[k + 2] = lut[l + 2];
      image[k + 3] = 255;
    }
  }
  const field = MODE_FIELDS[mode];
  if (field === undefined) throw new Error(`no colour mode ${JSON.stringify(mode)}`);
  const colours = legend.palettes[mode].map(rgbOf);
  const codes = frame.agents[field];
  const { x: ax, y: ay } = frame.agents;
  for (let i = 0; i < frame.n; i++) {
    const rgb = colours[codes[i]];
    if (rgb === undefined) throw new Error(`${mode} code ${codes[i]} has no colour in the legend`);
    const k = ((H - 1 - ay[i]) * W + ax[i]) * 4;
    image[k] = rgb[0];
    image[k + 1] = rgb[1];
    image[k + 2] = rgb[2];
  }
  return image;
}

/** tagString(tags, ntags): the agent's tags as 0s and 1s, tag 1 first (tag i is bit i - 1, as the model stores them). */
export function tagString(tags, ntags) {
  let s = "";
  for (let i = 0; i < ntags; i++) s += (tags >> i) & 1 ? "1" : "0";
  return s;
}

const cellIndex = new WeakMap(); // frame -> Int32Array: the agent in each cell, -1 for none

function agentAt(frame, x, y) {
  let index = cellIndex.get(frame);
  if (!index) {
    index = new Int32Array(frame.width * frame.height).fill(-1);
    for (let i = 0; i < frame.n; i++) index[frame.agents.y[i] * frame.width + frame.agents.x[i]] = i;
    cellIndex.set(frame, index);
  }
  return index[y * frame.width + x];
}

/**
 * hitTest(frame, x, y) -> {agent: {...}, cell: {...}} over an agent, {cell: {x, y, sugar, spice}} over an empty cell, or
 * null outside the map. Exact values: levels are the frame's eighths divided by 8, tags an `ntags`-character string.
 */
export function hitTest(frame, x, y) {
  if (!Number.isInteger(x) || !Number.isInteger(y) || x < 0 || y < 0 || x >= frame.width || y >= frame.height) return null;
  const c = y * frame.width + x;
  const cell = { x, y, sugar: frame.cellSugar8[c] / 8, spice: frame.cellSpice8[c] / 8 };
  const i = agentAt(frame, x, y);
  if (i < 0) return { cell };
  const a = frame.agents;
  return {
    agent: {
      id: a.id[i], x, y, tribe: a.tribe[i], tags: tagString(a.tags[i], frame.ntags), ones: a.ones[i], sugar: a.sugar[i],
      spice: a.spice[i], age: a.age[i], ndiseases: a.ndiseases[i], lent: a.lent[i], owed: a.owed[i], role: a.role[i],
    },
    cell,
  };
}

const painted = new WeakMap(); // context -> {frame, mode, legend, canvas}: the last base image, reused while only marks or hover change

function newCanvas(w, h) {
  if (typeof OffscreenCanvas !== "undefined") return new OffscreenCanvas(w, h);
  return Object.assign(document.createElement("canvas"), { width: w, height: h });
}

/**
 * drawMap(ctx, frame, recentFrames, mode, legend): the landscape and the agents, one cell each, scaled to the canvas
 * without smoothing (a whole number of device pixels per cell), then the marks of `markList(frame, recentFrames)`:
 * a cross at each kill's cell (the victim's) and a ring at each tribe change's, in the legend's colours, at
 * `markOpacity(age)`. Marks are drawn larger than a cell so they can be seen; their size means nothing.
 */
export function drawMap(ctx, frame, recentFrames, mode, legend) {
  const { width: W, height: H } = frame;
  let base = painted.get(ctx);
  if (!base || base.frame !== frame || base.mode !== mode || base.legend !== legend) {
    const canvas = base?.canvas.width === W && base.canvas.height === H ? base.canvas : newCanvas(W, H);
    canvas.getContext("2d").putImageData(new ImageData(paintMap(frame, mode, legend), W, H), 0, 0);
    base = { frame, mode, legend, canvas };
    painted.set(ctx, base);
  }
  const { width: cw, height: ch } = ctx.canvas;
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.globalAlpha = 1;
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(base.canvas, 0, 0, cw, ch);

  const k = cw / W; // device pixels per cell
  const dpr = globalThis.devicePixelRatio || 1;
  const arm = Math.max(1.5 * k, 3 * dpr);
  const radius = Math.max(2.5 * k, 4 * dpr);
  const lw = Math.max(1, Math.round(dpr));
  ctx.lineCap = "butt";
  // One path per kind and age (early periods have thousands of marks each), oldest first so the newest are on top.
  const marks = markList(frame, recentFrames);
  for (let j = 0; j < marks.length;) {
    const { kind, age, opacity } = marks[j];
    ctx.globalAlpha = opacity;
    ctx.beginPath();
    for (; j < marks.length && marks[j].kind === kind && marks[j].age === age; j++) {
      const cx = (marks[j].x + 0.5) * k;
      const cy = (H - 1 - marks[j].y + 0.5) * (ch / H);
      if (kind === "kill") {
        ctx.moveTo(cx - arm, cy - arm);
        ctx.lineTo(cx + arm, cy + arm);
        ctx.moveTo(cx - arm, cy + arm);
        ctx.lineTo(cx + arm, cy - arm);
      } else {
        ctx.moveTo(cx + radius, cy);
        ctx.arc(cx, cy, radius, 0, 2 * Math.PI);
      }
    }
    ctx.strokeStyle = kind === "kill" ? legend.kill_colour : legend.change_colour;
    ctx.lineWidth = kind === "kill" ? lw : 1.5 * lw;
    ctx.stroke();
  }
  ctx.restore();
}
