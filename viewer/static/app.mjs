// The viewer page: fetches periods from the local server and draws them. Every color, size and legend entry
// comes from encoding.mjs; this file defines no encoding of its own.
import { boardPixels, cellAt, paintCells } from "./board.mjs";
import { FrameCache } from "./cache.mjs";
import {
  COLOR_MODES, OUTLINE, OUTLINE_WIDTH, PALETTES, SIZE_MODES, cellColor, formatWealth, legendCells, wealth,
} from "./encoding.mjs";
import { pause } from "./pace.mjs";
import { PopulationSeries } from "./series.mjs";

const PREFETCH = 4; // periods requested ahead of the next one while playing (at most 5 in flight)
const DEFAULT_EXPERIMENT = "VI-1"; // selected when the page opens: all rules on

const $ = (id) => document.getElementById(id);
const els = {
  form: $("start"), experiment: $("experiment"), seed: $("seed"), xl: $("xl"), runInfo: $("run-info"),
  error: $("error"), board: $("board"), captionT: $("caption-t"), captionSize: $("caption-size"), back: $("back"), play: $("play"), forward: $("forward"),
  slider: $("slider"), speed: $("speed"), status: $("status"), chart: $("chart"),
  colorBy: $("color-by"), sizeBy: $("size-by"), legendCells: $("legend-cells"), legendAgents: $("legend-agents"),
  hover: $("hover"),
};

const state = {
  info: null, // the run's /api/run response
  runId: 0, // bumped per run, so late responses from an old run are dropped
  startSeq: 0, // bumped per Start press, so only the latest press sets up the page
  frame: null, // decoded frame on the board
  target: 0, // the period the user last asked to see
  latest: 0,
  earliest: 0, // oldest period the server still keeps (it keeps the newest info.keep)
  populations: new PopulationSeries(),
  popRequest: null,
  cache: new FrameCache(false), // replaced per run, sized for its world
  inflight: new Map(), // t -> promise
  playing: false,
  playGen: 0, // bumped on every play/pause, so only the newest playback loop may draw
  hoverCell: null,
  boardPx: null, // xl: the board's size in device pixels, set on the first draw and on resize
  xlImage: null, // xl: { frame, mode, canvas } painted one pixel per cell, reused while only the hover moves
};

// The palette the current run is drawn in (encoding.mjs): xl runs have their own.
const palette = () => (state.info?.xl ? PALETTES.xl : PALETTES.regular);

// --- data ------------------------------------------------------------------------------------

async function api(path, body) {
  const response = await fetch(path, body === undefined ? {} : {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
  });
  const json = await response.json();
  if (!response.ok) throw new Error(json.error ?? `HTTP ${response.status}`);
  return json;
}

function showError(err) {
  els.error.textContent = err ? `Error: ${err.message ?? err}` : "";
}

// Columns to one object per agent, plus a cell -> agent index for hover.
function decode(json) {
  const a = json.agents;
  const agents = a.id.map((id, i) => ({
    id, x: a.x[i], y: a.y[i], sugar: a.sugar[i], spice: a.spice[i], tribe: a.tribe[i],
    vision: a.vision[i], metabolism: a.metabolism[i], age: a.age[i], sex: a.sex[i],
  }));
  const at = new Map(agents.map((g) => [g.x * state.info.height + g.y, g]));
  return { t: json.t, population: json.population, sugar: json.sugar, spice: json.spice, agents, at };
}

function fetchFrame(t) {
  if (state.cache.has(t)) return Promise.resolve(state.cache.get(t));
  if (state.inflight.has(t)) return state.inflight.get(t);
  const runId = state.runId;
  const request = api(`/api/frame?run=${state.info.run}&t=${t}`).then((json) => {
    if (runId !== state.runId) throw new Error("stale run");
    const frame = decode(json);
    state.cache.set(t, frame);
    setLatest(json.latest, json.earliest);
    return frame;
  }).finally(() => {
    if (runId === state.runId) state.inflight.delete(t);
  });
  state.inflight.set(t, request);
  return request;
}

function setLatest(latest, earliest) {
  if (earliest > state.earliest) {
    state.earliest = earliest;
    els.slider.min = String(earliest);
    state.cache.dropBefore(earliest);
  }
  if (latest <= state.latest) return;
  state.latest = latest;
  els.slider.max = String(latest);
  refreshPopulations();
}

function refreshPopulations() {
  if (state.popRequest || state.populations.length > state.latest) return;
  const runId = state.runId;
  state.popRequest = api(`/api/population?run=${state.info.run}&from=${state.populations.length}`).then((json) => {
    if (runId !== state.runId) return;
    setLatest(json.latest, json.earliest);
    state.populations.append(json.from, json.counts);
    drawChart();
    updateStatus();
  }).catch(showError).finally(() => {
    if (runId === state.runId) {
      state.popRequest = null;
      if (state.populations.length <= state.latest) refreshPopulations();
    }
  });
}

// Show period t on the board, unless the user has since asked for another.
async function goTo(t) {
  if (!state.info) return;
  t = Math.max(state.earliest, Math.min(t, state.latest + 1));
  state.target = t;
  try {
    const frame = await fetchFrame(t);
    if (state.target === t) setFrame(frame);
  } catch (err) {
    if (err.message !== "stale run") showError(err);
  }
}

function setFrame(frame) {
  state.frame = frame;
  els.slider.value = String(frame.t);
  els.captionT.textContent = String(frame.t);
  drawBoard();
  drawChart();
  updateStatus();
  updateHover();
}

// --- playback -------------------------------------------------------------------------------

function setPlaying(on) {
  state.playing = on && Boolean(state.info);
  state.playGen += 1;
  els.play.textContent = state.playing ? "Pause" : "Play";
  if (state.playing) playLoop(state.playGen);
}

// One loop per Play press. A loop still awaiting a frame or its timer when the user pauses and plays again
// finds a newer generation and ends, so two loops never advance the board at once.
async function playLoop(gen) {
  const current = () => gen === state.playGen;
  while (current()) {
    const started = performance.now();
    const next = (state.frame?.t ?? 0) + 1;
    for (let k = 1; k <= PREFETCH; k++) fetchFrame(next + k).catch(() => {});
    let frame;
    try {
      frame = await fetchFrame(next);
    } catch (err) {
      if (!current()) return;
      if (err.message !== "stale run") showError(err);
      setPlaying(false);
      return;
    }
    if (!current()) return;
    state.target = frame.t;
    setFrame(frame);
    await pause(els.speed.value, performance.now() - started);
  }
}

// --- drawing --------------------------------------------------------------------------------

// Size a canvas's backing store to its CSS box times the device pixel ratio, keeping whole pixels per cell.
function fitCanvas(canvas, cells) {
  const rect = canvas.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  let w = Math.round(rect.width * dpr);
  let h = Math.round(rect.height * dpr);
  if (cells) {
    w = h = Math.max(cells, Math.floor(w / cells) * cells);
  }
  if (canvas.width !== w || canvas.height !== h) {
    canvas.width = w;
    canvas.height = h;
  }
  return { w, h, dpr };
}

function drawBoard() {
  const { info, frame } = state;
  if (!info || !frame) return;
  if (info.xl) return drawXlBoard();
  els.board.classList.remove("xl"); // back to the stylesheet's size after an xl run
  els.board.style.width = els.board.style.height = "";
  const { width: W, height: H } = info;
  const { w } = fitCanvas(els.board, W);
  const cell = w / W;
  const g = els.board.getContext("2d");
  for (let x = 0; x < W; x++) {
    for (let y = 0; y < H; y++) {
      const i = x * H + y;
      const [r, gr, b] = cellColor(frame.sugar[i], frame.spice ? frame.spice[i] : 0, info.sugar_max, info.spice_max,
        palette().weight);
      g.fillStyle = `rgb(${r},${gr},${b})`;
      g.fillRect(x * cell, (H - 1 - y) * cell, cell, cell);
    }
  }
  const color = COLOR_MODES[els.colorBy.value];
  const size = SIZE_MODES[els.sizeBy.value];
  g.strokeStyle = OUTLINE;
  g.lineWidth = Math.max(1, OUTLINE_WIDTH * cell);
  for (const agent of frame.agents) {
    g.fillStyle = color.color(agent, palette());
    g.beginPath();
    g.arc((agent.x + 0.5) * cell, (H - 1 - agent.y + 0.5) * cell, size.radius(agent) * cell, 0, 2 * Math.PI);
    g.fill();
    g.stroke();
  }
  if (state.hoverCell) {
    const [x, y] = state.hoverCell;
    g.strokeStyle = "#000";
    g.lineWidth = Math.max(1, cell / 8);
    g.strokeRect(x * cell, (H - 1 - y) * cell, cell, cell);
  }
}

// The element's content box in CSS px, unrounded (clientWidth and clientLeft round to whole CSS px, which at
// about one device pixel per cell is half a cell; the board's 1px border is 0.67 CSS px at devicePixelRatio 1.5).
function contentBox(el) {
  const r = el.getBoundingClientRect();
  const s = getComputedStyle(el);
  const [l, t, rt, b] = [s.borderLeftWidth, s.borderTopWidth, s.borderRightWidth, s.borderBottomWidth].map(parseFloat);
  return { left: r.left + l, top: r.top + t, width: r.width - l - rt, height: r.height - t - b };
}

// xl: one solid color per cell, every cell k x k device pixels (k whole, at least 1), never smoothed. The board's
// content box (class "xl": content-box sizing, so the border sits outside it) is set to exactly its pixels /
// devicePixelRatio, and it renders pixelated, so the browser doesn't resample it either (xl review #1).
function drawXlBoard() {
  const { info, frame } = state;
  const W = info.width, H = info.height;
  const dpr = window.devicePixelRatio || 1;
  if (state.boardPx === null) {
    els.board.classList.remove("xl"); // measure the content box the stylesheet gives the board
    els.board.style.width = els.board.style.height = "";
    state.boardPx = boardPixels(Math.floor(contentBox(els.board).width * dpr + 1e-6), W);
    els.board.classList.add("xl");
  }
  const n = state.boardPx;
  if (els.board.width !== n || els.board.height !== n) els.board.width = els.board.height = n;
  els.board.style.width = els.board.style.height = `${n / dpr}px`;
  const mode = els.colorBy.value;
  if (state.xlImage?.frame !== frame || state.xlImage.mode !== mode) {
    const canvas = state.xlImage?.canvas ?? document.createElement("canvas");
    canvas.width = W;
    canvas.height = H;
    const pixels = paintCells(frame, info, COLOR_MODES[mode], palette());
    canvas.getContext("2d").putImageData(new ImageData(pixels, W, H), 0, 0);
    state.xlImage = { frame, mode, canvas };
  }
  const g = els.board.getContext("2d");
  g.imageSmoothingEnabled = false;
  g.drawImage(state.xlImage.canvas, 0, 0, n, n);
  if (state.hoverCell) {
    const [x, y] = state.hoverCell;
    const k = n / W;
    g.strokeStyle = "#000";
    g.lineWidth = 1;
    g.strokeRect(x * k - 0.5, (H - 1 - y) * k - 0.5, k + 1, k + 1); // just outside the cell, which stays visible
  }
}

function niceStep(max, ticks) {
  const raw = max / ticks;
  const mag = 10 ** Math.floor(Math.log10(raw));
  return [1, 2, 5, 10].map((m) => m * mag).find((s) => s >= raw);
}

const chartBox = { left: 44, right: 10, top: 10, bottom: 24 };

function drawChart() {
  const { w, h, dpr } = fitCanvas(els.chart);
  const g = els.chart.getContext("2d");
  g.setTransform(dpr, 0, 0, dpr, 0, 0);
  const cw = w / dpr, ch = h / dpr;
  const css = getComputedStyle(document.documentElement);
  const style = { getPropertyValue: (name) => css.getPropertyValue(name).trim() };
  g.clearRect(0, 0, cw, ch);
  const pops = state.populations;
  const xmax = Math.max(1, pops.length - 1);
  const ymax = Math.max(1, pops.max);
  const ystep = niceStep(ymax, 4);
  const ytop = Math.ceil(ymax / ystep) * ystep;
  const xstep = niceStep(xmax, 5);
  const plotW = cw - chartBox.left - chartBox.right, plotH = ch - chartBox.top - chartBox.bottom;
  const px = (t) => chartBox.left + (t / xmax) * plotW;
  const py = (n) => chartBox.top + plotH - (n / ytop) * plotH;

  g.font = "11px system-ui, sans-serif";
  g.fillStyle = style.getPropertyValue("--muted");
  g.strokeStyle = style.getPropertyValue("--border");
  g.lineWidth = 1;
  g.textAlign = "right";
  g.textBaseline = "middle";
  for (let n = 0; n <= ytop; n += ystep) {
    g.beginPath(); g.moveTo(chartBox.left, py(n)); g.lineTo(cw - chartBox.right, py(n)); g.stroke();
    g.fillText(String(n), chartBox.left - 4, py(n));
  }
  g.textAlign = "center";
  g.textBaseline = "top";
  for (let t = 0; t <= xmax; t += xstep) g.fillText(String(t), px(t), ch - chartBox.bottom + 6);
  if (state.earliest > 0) { // periods no longer kept for the board: counted, but not reachable
    g.fillStyle = style.getPropertyValue("--border");
    g.globalAlpha = 0.35;
    g.fillRect(chartBox.left, chartBox.top, px(state.earliest) - chartBox.left, plotH);
    g.globalAlpha = 1;
  }

  if (pops.length) {
    g.strokeStyle = style.getPropertyValue("--accent");
    g.lineWidth = 1.5;
    g.beginPath();
    g.moveTo(px(0), py(pops.at(0)));
    for (let t = 1; t < pops.length; t++) g.lineTo(px(t), py(pops.at(t)));
    if (pops.length === 1) g.lineTo(px(0) + 1, py(pops.at(0)));
    g.stroke();
  }
  if (state.frame) {
    g.strokeStyle = style.getPropertyValue("--focus");
    g.lineWidth = 1.5;
    g.beginPath(); g.moveTo(px(state.frame.t), chartBox.top); g.lineTo(px(state.frame.t), chartBox.top + plotH); g.stroke();
  }
}

// --- legend, hover, status ------------------------------------------------------------------

function swatch(rgb) {
  const td = document.createElement("td");
  td.style.background = `rgb(${rgb.join(",")})`;
  return td;
}

function drawLegend() {
  const { info } = state;
  els.legendCells.replaceChildren();
  els.legendAgents.replaceChildren();
  if (!info) return;
  const cells = legendCells(info.sugar_max, info.spice_max, palette().weight);
  const table = document.createElement("table");
  table.className = "swatches";
  const caption = table.createCaption();
  caption.textContent = info.spice ? "Cells: sugar across, spice down" : "Cells: sugar level";
  const head = table.insertRow();
  head.append(Object.assign(document.createElement("th"), { textContent: info.spice ? "spice \\ sugar" : "sugar" }));
  for (const s of cells.sugar) head.append(Object.assign(document.createElement("th"), { textContent: String(s) }));
  cells.spice.forEach((p, j) => {
    const row = table.insertRow();
    row.append(Object.assign(document.createElement("th"), { textContent: info.spice ? String(p) : "" }));
    cells.sugar.forEach((_, i) => row.append(swatch(cells.colors[i][j])));
  });
  els.legendCells.append(table);
  const note = document.createElement("p");
  note.className = "legend-note";
  note.textContent = "Levels between whole numbers blend in proportion; hover for exact values.";
  els.legendCells.append(note);

  const color = COLOR_MODES[els.colorBy.value];
  if (info.xl) {
    els.legendAgents.append(agentList(`Agent color: ${color.label}`, color.legend(palette()), true));
    const off = document.createElement("p");
    off.className = "legend-note";
    off.textContent = "Size: off at xl. Each agent fills its cell, which is about one pixel.";
    els.legendAgents.append(off);
    return;
  }
  const size = SIZE_MODES[els.sizeBy.value];
  els.legendAgents.append(agentList(`Agent color: ${color.label}`, color.legend().map((e) => ({ ...e, radius: 0.4 }))));
  els.legendAgents.append(agentList(`Agent size: ${size.label} (dot within one cell)`,
    size.legend().map((e) => ({ ...e, color: COLOR_MODES.none.color() }))));
}

// Legend rows: a dot within a cell, or at xl (`filled`) the whole cell in the agent's color, as the board draws it.
function agentList(title, entries, filled = false) {
  const wrap = document.createElement("div");
  const h = document.createElement("p");
  h.className = "legend-note";
  h.textContent = title;
  const list = document.createElement("ul");
  list.className = "agent-legend";
  const CELL = 22;
  for (const e of entries) {
    const li = document.createElement("li");
    li.innerHTML = filled
      ? `<svg width="${CELL}" height="${CELL}" aria-hidden="true"><rect width="${CELL}" height="${CELL}" fill="${e.color}"/></svg>`
      : `<svg width="${CELL}" height="${CELL}" aria-hidden="true">
      <rect x="0.5" y="0.5" width="${CELL - 1}" height="${CELL - 1}" fill="none" stroke="currentColor" stroke-opacity="0.25"/>
      <circle cx="${CELL / 2}" cy="${CELL / 2}" r="${e.radius * CELL}" fill="${e.color}"
        stroke="${OUTLINE}" stroke-width="${Math.max(1, OUTLINE_WIDTH * CELL)}"/></svg>`;
    li.append(e.label);
    list.append(li);
  }
  wrap.append(h, list);
  return wrap;
}

function fmt(v) {
  if (v === null || v === undefined) return "—";
  return typeof v === "number" && !Number.isInteger(v) ? v.toFixed(2) : String(v);
}

function updateHover() {
  const { info, frame, hoverCell } = state;
  if (!info || !frame || !hoverCell) {
    els.hover.innerHTML = "<dt>—</dt><dd>Hover over the board.</dd>";
    return;
  }
  const [x, y] = hoverCell;
  const i = x * info.height + y;
  const rows = [
    ["cell", `(${x}, ${y})`],
    ["sugar", `${fmt(frame.sugar[i])} of ${info.sugar_capacity[i]}`],
  ];
  if (info.spice) rows.push(["spice", `${fmt(frame.spice[i])} of ${info.spice_capacity[i]}`]);
  const agent = frame.at.get(i);
  if (agent) {
    rows.push(["agent", agent.id], ["wealth", formatWealth(wealth(agent))], ["sugar held", fmt(agent.sugar)],
      ["spice held", fmt(agent.spice)], ["tribe", fmt(agent.tribe)], ["vision", agent.vision],
      ["metabolism", agent.metabolism], ["age", agent.age], ["sex", fmt(agent.sex)]);
  } else {
    rows.push(["agent", "none"]);
  }
  els.hover.replaceChildren(...rows.flatMap(([k, v]) => [
    Object.assign(document.createElement("dt"), { textContent: k }),
    Object.assign(document.createElement("dd"), { textContent: String(v) }),
  ]));
}

function updateStatus() {
  const { frame } = state;
  els.status.textContent = frame
    ? `t = ${frame.t} · population ${frame.population} · computed to t = ${state.latest}` +
      (state.earliest > 0 ? ` · kept from t = ${state.earliest} (the newest ${state.info.keep})` : "")
    : "";
}

// --- menus and run setup --------------------------------------------------------------------

function fillMenus() {
  const info = state.info;
  const keep = els.colorBy.value;
  els.colorBy.replaceChildren(...Object.entries(COLOR_MODES).map(([key, mode]) => {
    const option = new Option(mode.label, key);
    option.disabled = !info || !mode.available(info);
    return option;
  }));
  const usable = (key) => key && COLOR_MODES[key] && (!info || COLOR_MODES[key].available(info));
  els.colorBy.value = usable(keep) && keep !== "none" ? keep : usable("tribe") ? "tribe" : "none";
  if (!els.sizeBy.options.length) {
    els.sizeBy.replaceChildren(...Object.entries(SIZE_MODES).map(([key, mode]) => new Option(mode.label, key)));
    els.sizeBy.value = "wealth";
  }
}

async function startRun(experiment, seed, xl) {
  setPlaying(false);
  showError(null);
  try {
    const seq = ++state.startSeq;
    const info = await api("/api/run", { experiment, seed, xl });
    if (seq !== state.startSeq) return; // a later Start press owns the page
    state.runId += 1;
    Object.assign(state, {
      info, frame: null, target: 0, latest: 0, earliest: 0, populations: new PopulationSeries(),
      popRequest: null, hoverCell: null, boardPx: null, xlImage: null,
    });
    state.cache = new FrameCache(info.xl);
    state.inflight.clear();
    els.slider.max = "0";
    els.slider.min = "0";
    els.runInfo.textContent = `${info.experiment}: ${info.title} ${info.rules} · seed ${info.seed} ` +
      `(run index ${info.seed_index}) · registered length ${info.steps} periods` + (info.xl ? " · xl 500 × 500" : "");
    els.captionSize.textContent = `${info.width} × ${info.height}`;
    els.sizeBy.disabled = info.xl; // every dot would be smaller than a pixel
    fillMenus();
    drawLegend();
    refreshPopulations();
    await goTo(0);
  } catch (err) {
    showError(err);
  }
}

async function init() {
  fillMenus();
  try {
    const experiments = await api("/api/experiments");
    els.experiment.replaceChildren(...experiments.map((e) => new Option(`${e.id} — ${e.title}`, e.id)));
    if (experiments.some((e) => e.id === DEFAULT_EXPERIMENT)) els.experiment.value = DEFAULT_EXPERIMENT;
  } catch (err) {
    showError(err);
  }

  els.form.addEventListener("submit", (event) => {
    event.preventDefault();
    const seed = Number(els.seed.value);
    if (!Number.isInteger(seed) || seed < 0) return showError(new Error("seed must be a whole number ≥ 0"));
    startRun(els.experiment.value, seed, els.xl.checked);
  });
  els.play.addEventListener("click", () => setPlaying(!state.playing));
  els.back.addEventListener("click", () => { setPlaying(false); goTo(state.target - 1); });
  els.forward.addEventListener("click", () => { setPlaying(false); goTo(state.target + 1); });
  els.slider.addEventListener("input", () => { setPlaying(false); goTo(Number(els.slider.value)); });
  els.colorBy.addEventListener("change", () => { drawBoard(); drawLegend(); });
  els.sizeBy.addEventListener("change", () => { drawBoard(); drawLegend(); });

  els.chart.addEventListener("click", (event) => {
    if (!state.populations.length) return;
    const rect = els.chart.getBoundingClientRect();
    const xmax = Math.max(1, state.populations.length - 1);
    const frac = (event.clientX - rect.left - chartBox.left) / (rect.width - chartBox.left - chartBox.right);
    setPlaying(false);
    goTo(Math.max(state.earliest, Math.min(state.latest, Math.floor(frac * xmax + 0.5))));
  });

  // Pointer events, not mouse events: their coordinates keep fractions of a CSS pixel, and an xl cell is 0.67 CSS px
  // at devicePixelRatio 1.5 (MouseEvent.clientX is a whole number, so some cells could never be hovered).
  els.board.addEventListener("pointermove", (event) => {
    if (!state.info) return;
    const { width: W, height: H } = state.info;
    const box = contentBox(els.board);
    const cell = cellAt(event.clientX - box.left, event.clientY - box.top, box.width, box.height, W, H);
    if (String(cell) !== String(state.hoverCell)) {
      state.hoverCell = cell;
      drawBoard();
      updateHover();
    }
  });
  els.board.addEventListener("pointerleave", () => { state.hoverCell = null; drawBoard(); updateHover(); });

  document.addEventListener("keydown", (event) => {
    if (event.target.closest("input, select, textarea, button") || !state.info) return;
    if (event.key === " ") { event.preventDefault(); setPlaying(!state.playing); }
    if (event.key === "ArrowLeft") { setPlaying(false); goTo(state.target - 1); }
    if (event.key === "ArrowRight") { setPlaying(false); goTo(state.target + 1); }
  });
  window.addEventListener("resize", () => { state.boardPx = null; drawBoard(); drawChart(); });
  drawChart();
}

init();
