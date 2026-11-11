// The charts: each a line over periods 0 to newest of a series the server sends (julia/viewer/run.jl, SERIES_KEYS), with a
// line at the period on the map, a dashed marker at 500 (where the study stops) and the periods no longer kept for the map
// shaded; plus the Lorenz curve of the period on the map. An undefined value (null in the series, NaN in a frame) is a gap,
// never 0. The geometry functions touch no DOM, so Node can import this module for julia/test/js/charts.test.mjs.

/** Where the combat study stops; marked on every chart. */
export const STUDY_END = 500;

const NEUTRAL = "#374151";
const SECOND = "#0f766e";

/**
 * The charts, in page order. A chart has one or more panels stacked over a shared period axis; each panel draws its
 * lines on its own y axis from 0 (`fixed` gives the axis top, else it grows with the largest value so far). A line's
 * `colour` is a colour or ["palette", mode, code] from the legend. Adding a chart (for example pollution) is one entry.
 */
export const CHARTS = [
  {
    id: "population", title: "Population by tribe",
    panels: [{ lines: [{ key: "n_blue", label: "blue", colour: ["palette", "tribe", 0] },
      { key: "n_red", label: "red", colour: ["palette", "tribe", 1] }] }],
  },
  {
    id: "kills", title: "Kills per period, by the victim's tribe",
    panels: [{ lines: [{ key: "killed_blue", label: "blue victims", colour: ["palette", "tribe", 0] },
      { key: "killed_red", label: "red victims", colour: ["palette", "tribe", 1] }] }],
  },
  {
    id: "changes", title: "Tribe changes per period",
    panels: [{ lines: [{ key: "tribe_changes", label: "agents whose tribe changed", colour: "#b38600" }] }],
  },
  {
    id: "gini", title: "Gini of wealth (sugar + spice)",
    panels: [{ fixed: 1, lines: [{ key: "gini", label: "Gini", colour: NEUTRAL }] }],
  },
  {
    id: "trade", title: "Trade",
    panels: [
      { lines: [{ key: "trades", label: "trades per period", colour: NEUTRAL }] },
      { lines: [{ key: "mean_price", label: "mean price (spice per sugar; none without trades)", colour: SECOND }] },
    ],
  },
  {
    id: "credit", title: "Credit",
    panels: [
      { lines: [{ key: "n_loans", label: "loans outstanding", colour: NEUTRAL }] },
      { lines: [{ key: "total_debt", label: "total debt: what borrowers owe (principal + interest)", colour: SECOND }] },
    ],
  },
  {
    id: "sick", title: "Share of agents sick",
    panels: [{ fixed: 1, lines: [{ key: "fraction_sick", label: "share sick", colour: "#b91c1c" }] }],
  },
];

const defined = (v) => typeof v === "number" && Number.isFinite(v);

/**
 * linePath(values, xOf, yOf) -> [[[x, y], ...], ...]: the polyline segments through the defined values, point i at
 * (xOf(i), yOf(values[i])), split wherever a value is null, undefined or NaN. A segment may be a single point.
 */
export function linePath(values, xOf, yOf) {
  const segments = [];
  let current = null;
  for (let i = 0; i < values.length; i++) {
    const v = values[i];
    if (!defined(v)) {
      current = null;
      continue;
    }
    if (!current) {
      current = [];
      segments.push(current);
    }
    current.push([xOf(i), yOf(v)]);
  }
  return segments;
}

/** The smallest of 1, 2, 5 times a power of ten that is at least v (v > 0). */
function niceCeil(v) {
  const mag = 10 ** Math.floor(Math.log10(v));
  for (const m of [1, 2, 5, 10]) if (m * mag >= v * (1 - 1e-12)) return m * mag;
  return 10 * mag;
}

/** yTop(arrays): a nice axis top at or above the largest defined value of all arrays; 1 when there is none above 0. */
export function yTop(arrays) {
  let max = 0;
  for (const a of arrays) for (const v of a) if (defined(v) && v > max) max = v;
  return max > 0 ? niceCeil(max) : 1;
}

/** xMax(newest): the period axis's end, a nice number at or above the newest period (at least 10). */
export function xMax(newest) {
  return Math.max(10, newest > 0 ? niceCeil(newest) : 10);
}

/** The plot area inside a chart canvas, in CSS px. */
export const PLOT = { left: 52, right: 12, top: 8, bottom: 22, gap: 14 };

/** periodAt(rect, clientX, newest): the period under a click at clientX on a chart whose box is `rect`. */
export function periodAt(rect, clientX, newest) {
  const frac = (clientX - rect.left - PLOT.left) / (rect.width - PLOT.left - PLOT.right);
  return Math.round(Math.min(1, Math.max(0, frac)) * xMax(newest));
}

function formatNumber(v) {
  if (!defined(v)) return "undefined";
  if (Number.isInteger(v)) return String(v);
  return String(Number(v.toPrecision(6)));
}

function tickLabel(v) {
  if (v === 0) return "0";
  if (Math.abs(v) >= 1e6) return `${v / 1e6}M`;
  if (Math.abs(v) >= 1e4) return `${v / 1e3}k`;
  return String(Number(v.toPrecision(3)));
}

/** readout(chart, series, t): the chart's values at period t, as text ("undefined" where the model left none). */
export function readout(chart, series, t) {
  return chart.panels.flatMap((p) => p.lines.map((l) => `${l.label} ${formatNumber(series[l.key]?.[t])}`)).join(" · ");
}

function lineColour(colour, legend) {
  if (!Array.isArray(colour)) return colour;
  return legend?.palettes?.[colour[1]]?.[colour[2]] ?? NEUTRAL;
}

/** Sizes a canvas's backing store to its CSS box times devicePixelRatio and scales the context to CSS px. */
export function fitCanvas(canvas) {
  const rect = canvas.getBoundingClientRect();
  const dpr = globalThis.devicePixelRatio || 1;
  const w = Math.max(1, Math.round(rect.width * dpr));
  const h = Math.max(1, Math.round(rect.height * dpr));
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
  }
  const g = canvas.getContext("2d");
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  return { g, w: w / dpr, h: h / dpr };
}

function strokeSegments(g, segments) {
  for (const seg of segments) {
    if (seg.length === 1) {
      g.beginPath();
      g.arc(seg[0][0], seg[0][1], 1.6, 0, 2 * Math.PI);
      g.fill();
      continue;
    }
    g.beginPath();
    g.moveTo(seg[0][0], seg[0][1]);
    for (let i = 1; i < seg.length; i++) g.lineTo(seg[i][0], seg[i][1]);
    g.stroke();
  }
}

const INK = { text: "#4b5563", grid: "#e5e7eb", axis: "#9ca3af", shade: "rgba(107, 114, 128, 0.16)", shown: "#e8603c" };

/**
 * drawChart(canvas, chart, series, view): one chart of CHARTS. `series` maps keys to arrays indexed by period;
 * `view` is {shown, oldestKept, newest, legend}: the period on the map, the oldest period still kept for it, the newest.
 */
export function drawChart(canvas, chart, series, view) {
  const { g, w, h } = fitCanvas(canvas);
  g.clearRect(0, 0, w, h);
  const newest = Math.max(0, view.newest ?? 0);
  const xm = xMax(newest);
  const plotW = w - PLOT.left - PLOT.right;
  const n = chart.panels.length;
  const panelH = (h - PLOT.top - PLOT.bottom - PLOT.gap * (n - 1)) / n;
  const px = (t) => PLOT.left + (t / xm) * plotW;
  g.font = "11px system-ui, sans-serif";
  g.lineJoin = "round";

  chart.panels.forEach((panel, p) => {
    const top = PLOT.top + p * (panelH + PLOT.gap);
    const ymax = panel.fixed ?? yTop(panel.lines.map((l) => series[l.key] ?? []));
    const py = (v) => top + panelH - (v / ymax) * panelH;
    // grid and y labels: 0, half, top
    g.lineWidth = 1;
    g.textAlign = "right";
    g.textBaseline = "middle";
    for (const v of [0, ymax / 2, ymax]) {
      g.strokeStyle = INK.grid;
      g.beginPath(); g.moveTo(PLOT.left, py(v)); g.lineTo(w - PLOT.right, py(v)); g.stroke();
      g.fillStyle = INK.text;
      g.fillText(tickLabel(v), PLOT.left - 4, py(v));
    }
    // periods no longer kept for the map
    if (view.oldestKept != null && view.oldestKept > 0) {
      g.fillStyle = INK.shade;
      g.fillRect(PLOT.left, top, px(view.oldestKept) - PLOT.left, panelH);
    }
    // the study's end
    if (STUDY_END <= xm) {
      g.strokeStyle = INK.axis;
      g.setLineDash([3, 3]);
      g.beginPath(); g.moveTo(px(STUDY_END), top); g.lineTo(px(STUDY_END), top + panelH); g.stroke();
      g.setLineDash([]);
    }
    for (const line of panel.lines) {
      const colour = lineColour(line.colour, view.legend);
      g.strokeStyle = colour;
      g.fillStyle = colour;
      g.lineWidth = 1.5;
      strokeSegments(g, linePath(series[line.key] ?? [], px, py));
    }
    if (view.shown != null) {
      g.strokeStyle = INK.shown;
      g.lineWidth = 1.5;
      g.beginPath(); g.moveTo(px(view.shown), top); g.lineTo(px(view.shown), top + panelH); g.stroke();
    }
    // the panel's key
    g.textAlign = "left";
    g.textBaseline = "top";
    let kx = PLOT.left + 4;
    for (const line of panel.lines) {
      g.fillStyle = lineColour(line.colour, view.legend);
      g.fillRect(kx, top + 3, 10, 3);
      g.fillStyle = INK.text;
      g.fillText(line.label, kx + 13, top);
      kx += 13 + g.measureText(line.label).width + 12;
    }
  });

  // period axis
  g.fillStyle = INK.text;
  g.textAlign = "center";
  g.textBaseline = "top";
  const step = xm / 5;
  for (let t = 0; t <= xm + 1e-9; t += step) g.fillText(String(Math.round(t)), px(t), h - PLOT.bottom + 5);
}

/**
 * drawLorenz(canvas, frame): the Lorenz curve of wealth at the frame's period (share of wealth held by the poorest share
 * of agents) against the line of equality; undefined points (no agents) leave the curve out.
 */
export function drawLorenz(canvas, frame) {
  const { g, w, h } = fitCanvas(canvas);
  g.clearRect(0, 0, w, h);
  const size = Math.min(w - PLOT.left - PLOT.right, h - PLOT.top - PLOT.bottom);
  const left = PLOT.left, top = PLOT.top;
  const px = (f) => left + f * size;
  const py = (f) => top + size - f * size;
  g.font = "11px system-ui, sans-serif";
  g.lineWidth = 1;
  g.strokeStyle = INK.grid;
  g.strokeRect(left, top, size, size);
  g.fillStyle = INK.text;
  g.textAlign = "right";
  g.textBaseline = "middle";
  for (const v of [0, 0.5, 1]) g.fillText(String(v), left - 4, py(v));
  g.textAlign = "center";
  g.textBaseline = "top";
  for (const v of [0, 0.5, 1]) g.fillText(String(v), px(v), top + size + 5);
  g.strokeStyle = INK.axis;
  g.setLineDash([3, 3]);
  g.beginPath(); g.moveTo(px(0), py(0)); g.lineTo(px(1), py(1)); g.stroke();
  g.setLineDash([]);
  if (!frame) return;
  const n = frame.lorenz.length - 1;
  g.strokeStyle = NEUTRAL;
  g.fillStyle = NEUTRAL;
  g.lineWidth = 1.75;
  strokeSegments(g, linePath(frame.lorenz, (i) => px(i / n), py));
  g.textAlign = "left";
  g.textBaseline = "top";
  g.fillStyle = INK.text;
  g.fillText(`t = ${frame.t} · Gini ${formatNumber(frame.gini)}`, left + 6, top + 4);
}
