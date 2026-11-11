// The xxl viewer page: starts a run on the local Julia server (julia/viewer/server.jl), follows it, and draws its frames
// and series. Every colour and encoding comes from map.mjs, charts.mjs and the server's legend; this file defines none.
import { CHARTS, drawChart, drawLorenz, periodAt, readout } from "./charts.mjs";
import { FrameCache } from "./cache.mjs";
import { decodeFrame } from "./frame.mjs";
import {
  MARK_WHEN, MARK_WHICH, drawMap, hitTest, landscapeColour, markPeriods, marksNote, marksOverlap, marksToDraw,
} from "./map.mjs";

const POLL_MS = 1000; // /api/status
const PREFETCH = 4; // frames requested ahead of the next one while playing
const TERMINAL = new Set(["stopped", "extinct", "failed"]); // states after which no new period comes
const MODE_LABELS = {
  tribe: "Tribe", culture: "Culture shade (tags set)", wealth: "Wealth (sugar + spice)", disease: "Diseases carried",
  credit: "Credit role",
};

const $ = (id) => document.getElementById(id);
const els = {
  form: $("start"), experiment: $("experiment"), seed: $("seed"), seedNote: $("seed-note"), h: $("h"), k: $("k"),
  startButton: $("start-button"), stop: $("stop"), settings: $("settings"), status: $("status"), error: $("error"),
  map: $("map"), marksNote: $("marks-note"), marksOverlap: $("marks-overlap"), captionT: $("caption-t"), back: $("back"), play: $("play"), forward: $("forward"),
  slider: $("slider"), period: $("period"), speed: $("speed"), note: $("note"), colourBy: $("colour-by"),
  marksWhen: $("marks-when"), marksWhich: $("marks-which"),
  legendAgents: $("legend-agents"), legendMarks: $("legend-marks"), legendCells: $("legend-cells"), hover: $("hover"),
  charts: $("charts"),
};

const state = {
  experiments: [],
  legend: null, // the current run's legend (or the default experiment's before any run)
  run: null, // the current run's id
  settings: null,
  runIndex: null,
  newest: -1, // newest period computed, from /api/status
  oldestKept: null, // oldest period whose frame the server keeps
  runState: "idle",
  runError: null,
  series: {}, // key -> values by period (null where the model left the value undefined)
  seriesBusy: false,
  cache: new FrameCache(),
  inflight: new Map(), // t -> promise of a frame (or null when not kept)
  frame: null, // the frame on the map
  recent: [], // "fading" marks: the kept frames of the 9 periods before it
  failed: [], // periods among those whose frames failed to load
  marks: [], // the marks drawn (marksToDraw)
  marksNote: "", // "fading" marks: which periods' marks are missing, if any
  marksOverlap: "", // how the drawn marks share cells, if any do (marksOverlap)
  target: null, // the period last asked for
  scrubTarget: null,
  scrubbing: false,
  playing: false,
  playGen: 0, // bumped on every play / pause, so only the newest play loop advances
  statusWaiters: [],
  hover: null, // [x, y]
  starting: false,
  epoch: 0, // bumped when the page takes a run, so a status answered before that is not acted on
  mapPixels: 0, // the map's backing store, device pixels a side
};

class StaleRun extends Error {}

// --- server ---------------------------------------------------------------------------------------------------------

async function api(path, options = {}) {
  const response = await fetch(path, { cache: "no-store", ...options });
  const json = await response.json().catch(() => ({}));
  if (!response.ok) {
    const err = new Error(json.error ?? `HTTP ${response.status}`);
    err.status = response.status;
    throw err;
  }
  return json;
}

function showError(err) {
  els.error.textContent = err ? String(err.message ?? err) : "";
}

// The frame of period t of the current run, from the cache or the server: null when the server no longer keeps it (or
// does not have it yet). A request moves the server's backpressure point to t, but a cache hit asks the server nothing,
// so the period shown is reported on its own (reportShown, and every status poll).
function fetchFrame(t) {
  if (state.cache.has(t)) return Promise.resolve(state.cache.get(t));
  if (state.inflight.has(t)) return state.inflight.get(t);
  const run = state.run;
  const request = (async () => {
    const response = await fetch(`/api/frame?run=${run}&t=${t}`, { cache: "no-store" });
    if (response.status === 404) return null;
    if (response.status === 409 || run !== state.run) throw new StaleRun(`run ${run} is no longer current`);
    if (!response.ok) throw new Error(`frame ${t}: HTTP ${response.status}`);
    const frame = decodeFrame(await response.arrayBuffer());
    if (run !== state.run) throw new StaleRun(`run ${run} is no longer current`);
    if (state.oldestKept === null || t >= state.oldestKept) state.cache.set(t, frame);
    return frame;
  })().finally(() => {
    if (run === state.run) state.inflight.delete(t);
  });
  state.inflight.set(t, request);
  return request;
}

// Show period t. With marks from "last 10 periods, fading", first fetch the kept frames of the 9 periods before it, then
// t itself, so the last request is the period shown; with "this period" or "none" only t is fetched (markPeriods).
// Returns false when t is not kept or the user has since asked for another period. A mark frame that is not kept adds no
// marks and the marks note says so; one that fails is shown as an error and listed there too. Any other error (the
// shown frame failing, or drawing it) is thrown to the caller, which shows it.
async function showPeriod(t) {
  const run = state.run;
  if (run === null) return false;
  state.target = t;
  const failed = [];
  const earlier = markPeriods(t, els.marksWhen.value, state.oldestKept).filter((u) => u !== t).map((u) =>
    fetchFrame(u).catch((err) => {
      if (!(err instanceof StaleRun)) {
        failed.push(u);
        showError(new Error(`The frame of t = ${u} (for the marks) could not be loaded: ${err.message}`));
      }
      return null;
    }));
  const recent = (await Promise.all(earlier)).filter(Boolean);
  if (run !== state.run || state.target !== t) return false;
  const frame = await fetchFrame(t);
  if (run !== state.run || state.target !== t || !frame) return false;
  state.frame = frame;
  state.recent = recent;
  state.failed = failed;
  reportShown();
  updateMarks();
  render();
  return true;
}

// The status query that tells the server which period of the current run is on the map, whether its frame came from
// the server or the cache: the stepper stays at most `keep ÷ 2` periods ahead of it. Empty while nothing is shown.
function shownQuery() {
  return state.run !== null && state.frame ? `?run=${state.run}&shown=${state.frame.t}` : "";
}

// Report the period just shown at once, so the stepper (and so Play) need not wait for the next status poll. Its answer
// is not used: the poll reads the status, and says so if the server does not answer.
function reportShown() {
  fetch(`/api/status${shownQuery()}`, { cache: "no-store" }).catch(() => {});
}

// The marks for the frame shown, from the marks menus and the frames obtained; the missing-marks note in "fading" only.
function updateMarks() {
  const { frame } = state;
  const when = els.marksWhen.value;
  if (!frame) {
    state.marks = [];
    state.marksNote = "";
    state.marksOverlap = "";
    return;
  }
  state.marks = marksToDraw(frame.t, when, els.marksWhich.value, [frame, ...state.recent]);
  state.marksOverlap = marksOverlap(frame.t, when, els.marksWhich.value, [frame, ...state.recent]);
  state.marksNote = when === "fading"
    ? marksNote(frame.t, state.oldestKept ?? 0, [frame.t, ...state.recent.map((f) => f.t)], state.failed)
    : "";
}

// Shows an error unless it only says the run was replaced (the page then follows the new run).
function reportUnlessStale(err) {
  if (!(err instanceof StaleRun)) showError(err);
}

// Runs a redraw from an event handler, showing what it throws instead of losing it.
function safely(draw) {
  try {
    draw();
  } catch (err) {
    showError(err);
  }
}

// Slider and keyboard moves: show the latest period asked for, one fetch at a time.
async function scrubTo(t) {
  state.scrubTarget = t;
  if (state.scrubbing) return;
  state.scrubbing = true;
  try {
    while (state.scrubTarget !== null && state.scrubTarget !== state.frame?.t) {
      const want = state.scrubTarget;
      const shown = await showPeriod(want);
      if (!shown && state.scrubTarget === want) {
        els.note.textContent = `Period ${want} is not kept for the map.`;
        break;
      }
    }
  } catch (err) {
    reportUnlessStale(err);
  } finally {
    state.scrubbing = false;
    state.scrubTarget = null;
  }
}

function step(delta) {
  setPlaying(false);
  const t = (state.frame?.t ?? 0) + delta;
  if (state.run === null || t < (state.oldestKept ?? 0) || t > state.newest) return;
  els.note.textContent = "";
  scrubTo(t);
}

// --- status and series ----------------------------------------------------------------------------------------------

function nextStatus() {
  return new Promise((resolve) => state.statusWaiters.push(resolve));
}

async function pollStatus() {
  const epoch = state.epoch;
  try {
    const status = await api(`/api/status${shownQuery()}`);
    if (epoch !== state.epoch) return; // answered before the page took its current run (a Start crossed it)
    if (status.run !== null && status.run !== state.run && !state.starting) {
      // A run this page did not start (opened on a running server, or started from another tab): follow it.
      adoptRun(status.run, status.settings, status.run_index, { show: "newest" });
    }
    if (status.run === state.run) {
      state.newest = status.newest ?? -1;
      state.oldestKept = status.oldest_kept;
      state.runState = status.state;
      state.runError = status.error;
      if (state.oldestKept !== null) state.cache.dropBefore(state.oldestKept);
      if ((state.series.t?.length ?? 0) <= state.newest) fetchSeries();
    }
    updateStatus();
    updateTimeControls();
  } catch (err) {
    els.status.textContent = `The server does not answer (${err.message}). Is julia/xxl_viewer.jl running?`;
  } finally {
    const waiters = state.statusWaiters.splice(0);
    for (const resolve of waiters) resolve();
    setTimeout(pollStatus, POLL_MS);
  }
}

// The series from the first period the page lacks to the newest; a response for another run, or one that does not
// continue what the page has, is dropped.
async function fetchSeries() {
  if (state.seriesBusy || state.run === null) return;
  state.seriesBusy = true;
  const run = state.run;
  const from = state.series.t?.length ?? 0;
  try {
    const json = await api(`/api/series?run=${run}&from=${from}`);
    if (json.run !== state.run || run !== state.run || json.t0 !== (state.series.t?.length ?? 0)) return;
    for (const [key, values] of Object.entries(json.series)) {
      const target = state.series[key] ?? (state.series[key] = []);
      for (const v of values) target.push(v);
    }
    drawCharts();
  } catch (err) {
    if (err.status !== 409) showError(err);
  } finally {
    state.seriesBusy = false;
  }
}

// --- runs -------------------------------------------------------------------------------------------------------------

// Make run `id` the page's: everything from an earlier run is dropped. `show` is the period to show first.
function adoptRun(id, settings, runIndex, { show }) {
  if (id === state.run) return false;
  setPlaying(false);
  Object.assign(state, {
    run: id, settings, runIndex, newest: -1, oldestKept: null, runState: "running", runError: null, series: {},
    seriesBusy: false, cache: new FrameCache(), inflight: new Map(), frame: null, recent: [], failed: [], marks: [],
    marksNote: "", marksOverlap: "",
    target: null, scrubTarget: null, epoch: state.epoch + 1,
  });
  els.note.textContent = "";
  updateSettings();
  safely(render);
  loadLegend().then(async () => {
    if (state.run !== id || show !== "newest") return;
    if (state.newest < 0) await nextStatus();
    if (state.run === id && state.newest >= 0) await showPeriod(state.newest);
  }).catch(reportUnlessStale);
  return true;
}

// The current run's legend (the default experiment's before any run); dropped if the page has since taken another run.
async function loadLegend() {
  const run = state.run;
  try {
    const legend = await api("/api/legend");
    if (run !== state.run) return;
    state.legend = legend;
    fillColourMenu();
    drawLegend();
    render();
  } catch (err) {
    showError(err);
  }
}

async function startRun() {
  showError(null);
  const body = new URLSearchParams({
    exp: els.experiment.value, seed: els.seed.value.trim(), h: els.h.value.trim(), k: els.k.value.trim(),
  });
  state.starting = true;
  els.startButton.disabled = true;
  els.status.textContent = "Starting: building the run's model…";
  try {
    const json = await api("/api/start", { method: "POST", body });
    adoptRun(json.run, json.settings, json.run_index, { show: "first" });
    state.newest = Math.max(state.newest, 0);
    state.oldestKept = state.oldestKept ?? 0;
    try {
      await showPeriod(0);
      if (state.run === json.run) setPlaying(true);
    } catch (err) {
      reportUnlessStale(err); // the run started, but its first frame could not be shown
    }
  } catch (err) {
    showError(err.status === 400 ? new Error(`Not started: ${err.message}`) : err); // the current run carries on
  } finally {
    state.starting = false;
    els.startButton.disabled = false;
  }
}

async function stopRun() {
  try {
    await api("/api/stop", { method: "POST" });
  } catch (err) {
    showError(err);
  }
}

// --- playback ---------------------------------------------------------------------------------------------------------

const channel = new MessageChannel();
const turns = [];
channel.port1.onmessage = () => turns.shift()?.();

// Wait out the rest of one period at `speed` periods a second ("max": no wait, but one macrotask turn), given the time it
// already took (from viewer/static/pace.mjs).
function pace(speed, elapsedMs) {
  const wait = speed === "max" ? 0 : 1000 / Number(speed) - elapsedMs;
  if (wait > 0) return new Promise((resolve) => setTimeout(resolve, wait));
  return new Promise((resolve) => {
    turns.push(resolve);
    channel.port2.postMessage(null);
  });
}

function setPlaying(on) {
  state.playing = on && state.run !== null;
  state.playGen += 1;
  els.play.textContent = state.playing ? "Pause" : "Play";
  if (state.playing) playLoop(state.playGen);
}

// One loop per Play press, never ahead of what is computed: at the newest period it waits for the next status poll.
async function playLoop(gen) {
  const current = () => gen === state.playGen;
  while (current()) {
    const started = performance.now();
    let next = (state.frame?.t ?? -1) + 1;
    if (state.oldestKept !== null && next < state.oldestKept) next = state.oldestKept;
    if (next > state.newest) {
      if (TERMINAL.has(state.runState)) return setPlaying(false);
      await nextStatus();
      continue;
    }
    // Fetched ahead only to have them ready: a failure is not cached, and showing that period fetches it again and
    // reports any error then.
    for (let k = 1; k <= PREFETCH && next + k <= state.newest; k++) fetchFrame(next + k).catch(() => {});
    let shown;
    try {
      shown = await showPeriod(next);
    } catch (err) {
      if (!current()) return;
      reportUnlessStale(err);
      return setPlaying(false);
    }
    if (!current()) return;
    if (!shown) {
      await nextStatus(); // not kept (or not yet published): the next status says what is
      continue;
    }
    await pace(els.speed.value, performance.now() - started);
  }
}

// --- drawing ----------------------------------------------------------------------------------------------------------

// The map's size: a whole number of device pixels per cell, and at least one CSS pixel per cell, as large as the window
// comfortably allows. Its CSS size is exactly its device pixels, so `image-rendering: pixelated` never resamples it.
function sizeMap(width) {
  const dpr = window.devicePixelRatio || 1;
  const avail = Math.min(window.innerWidth * 0.6, window.innerHeight - 160);
  const k = Math.max(Math.ceil(dpr - 1e-9), Math.floor((avail * dpr) / width));
  const n = k * width;
  if (els.map.width !== n || els.map.height !== n) {
    els.map.width = n;
    els.map.height = n;
  }
  els.map.style.width = els.map.style.height = `${n / dpr}px`;
  state.mapPixels = n;
}

function drawMapNow() {
  const { frame, legend } = state;
  const g = els.map.getContext("2d");
  if (!frame || !legend) {
    sizeMap(500);
    g.fillStyle = "#ffffff";
    g.fillRect(0, 0, els.map.width, els.map.height);
    return;
  }
  sizeMap(frame.width);
  drawMap(g, frame, state.marks, els.colourBy.value, legend);
  if (state.hover) {
    const [x, y] = state.hover;
    const k = els.map.width / frame.width;
    g.strokeStyle = "#000000";
    g.lineWidth = Math.max(1, Math.round(window.devicePixelRatio || 1));
    g.strokeRect(x * k - 1.5, (frame.height - 1 - y) * k - 1.5, k + 3, k + 3); // just outside the cell
  }
}

const chartEls = new Map(); // chart id -> {canvas, value}

function buildCharts() {
  for (const chart of [...CHARTS, { id: "lorenz", title: "Lorenz curve of wealth at the period on the map", panels: [] }]) {
    const fig = document.createElement("figure");
    fig.className = `chart${chart.panels.length > 1 ? " two-panels" : ""}${chart.id === "lorenz" ? " lorenz" : ""}`;
    const title = Object.assign(document.createElement("h3"), { textContent: chart.title, id: `chart-${chart.id}` });
    const canvas = document.createElement("canvas");
    canvas.setAttribute("role", "img");
    canvas.setAttribute("aria-labelledby", `chart-${chart.id}`);
    const value = Object.assign(document.createElement("p"), { className: "value" });
    if (chart.id === "lorenz") {
      value.textContent = "Share of wealth (sugar + spice) held by the poorest share of agents; dashed: equality.";
    } else {
      canvas.addEventListener("click", (event) => {
        if (state.run === null || state.newest < 0) return;
        const t = periodAt(canvas.getBoundingClientRect(), event.clientX, state.newest);
        setPlaying(false);
        if (t < (state.oldestKept ?? 0) || t > state.newest) {
          els.note.textContent = `Period ${t} is no longer kept for the map (kept: ${state.oldestKept} to ${state.newest}).`;
          return;
        }
        els.note.textContent = "";
        scrubTo(t);
      });
    }
    fig.append(title, canvas, value);
    els.charts.append(fig);
    chartEls.set(chart.id, { canvas, value });
  }
}

function drawCharts() {
  const view = { shown: state.frame?.t ?? null, oldestKept: state.oldestKept, newest: state.newest, legend: state.legend };
  const t = state.frame?.t;
  for (const chart of CHARTS) {
    const { canvas, value } = chartEls.get(chart.id);
    drawChart(canvas, chart, state.series, view);
    value.textContent = t !== undefined && (state.series.t?.length ?? 0) > t ? `t = ${t}: ${readout(chart, state.series, t)}` : "";
  }
  drawLorenz(chartEls.get("lorenz").canvas, state.frame);
}

function render() {
  els.marksNote.textContent = state.frame ? state.marksNote : "";
  els.marksOverlap.textContent = state.frame ? state.marksOverlap : "";
  updateTimeControls();
  updateHover();
  drawMapNow();
  drawCharts();
}

// --- legend, hover, status ------------------------------------------------------------------------------------------

function fillColourMenu() {
  const keep = els.colourBy.value;
  els.colourBy.replaceChildren(...state.legend.modes.map((m) => new Option(MODE_LABELS[m] ?? m, m)));
  els.colourBy.value = state.legend.modes.includes(keep) ? keep : state.legend.modes[0];
}

function swatchItem(colour, label) {
  const li = document.createElement("li");
  const box = Object.assign(document.createElement("span"), { className: "swatch" });
  box.style.background = colour;
  li.append(box, label);
  return li;
}

function legendTitle(text) {
  return Object.assign(document.createElement("p"), { className: "legend-title", textContent: text });
}

function legendNote(text) {
  return Object.assign(document.createElement("p"), { className: "legend-note", textContent: text });
}

function drawLegend() {
  const legend = state.legend;
  if (!legend) return;
  const mode = els.colourBy.value;
  const list = Object.assign(document.createElement("ul"), { className: "swatch-list" });
  legend.palettes[mode].forEach((c, i) => list.append(swatchItem(c, legend.labels[mode][i])));
  const notes = {
    tribe: "The model's tribe label: blue when an agent's 0-tags outnumber its 1-tags.",
    culture: `How many of the ${legend.ntags} tags are 1: ${Math.ceil(legend.ntags / 2) - 1} or fewer is the blue ` +
      `tribe, ${Math.ceil(legend.ntags / 2)} or more the red.`,
    wealth: "Sugar + spice held, in bands fixed for all runs; the last band is open-ended.",
    disease: "How many diseases the agent carries.",
    credit: "The agent's part in the model's active loans.",
  };
  els.legendAgents.replaceChildren(legendTitle(`Agents: ${MODE_LABELS[mode] ?? mode}`), list,
    ...(notes[mode] ? [legendNote(notes[mode])] : []));

  const when = els.marksWhen.value;
  const which = els.marksWhich.value;
  const marks = Object.assign(document.createElement("ul"), { className: "swatch-list" });
  if (when !== "none" && which !== "switches") {
    marks.append(swatchItem(legend.kill_colour, "kill: the cell where the victim died"));
  }
  if (when !== "none" && which !== "kills") {
    marks.append(swatchItem(legend.change_colour, "tribe switch: the cell of an agent whose tribe changed"));
  }
  const whenText = {
    now: "Marks from this period: the events of the period shown.",
    fading: `Marks from the last ${legend.mark_periods} periods, fading: a mark of age a (0 to ` +
      `${legend.mark_periods - 1}, 0 the period shown) is blended over its cell at opacity 1 − a / ` +
      `${legend.mark_periods}, the newest on top.`,
    none: "Marks: none. The map shows the agents and the landscape only.",
  }[when];
  els.legendMarks.replaceChildren(legendTitle("Marks, in every colouring"), marks, legendNote(whenText),
    ...(when === "none" ? [] : [
      legendNote("Each mark fills exactly the cell where it happened, nothing larger, so it hides the agent standing " +
        "on that cell; hover still reads the agent. \"Show\" picks kills, switches or both."),
      legendNote("A cell with both a kill and a switch shows the kill (switches are drawn first, kills on top)."),
      legendNote("A cell can hold several events; the line under the map then says how many events fall on how many " +
        "cells."),
      legendNote("In \"last 10 periods, fading\", marks on one cell blend in order, oldest first, so a cell marked in " +
        "several periods shows darker than one mark's opacity."),
    ]));

  const levels = Array.from({ length: legend.max_level + 1 }, (_, i) => i);
  const table = Object.assign(document.createElement("table"), { className: "cells" });
  const head = table.insertRow();
  head.append(Object.assign(document.createElement("th"), { textContent: "spice \\ sugar" }));
  for (const s of levels) head.append(Object.assign(document.createElement("th"), { textContent: String(s) }));
  for (const p of levels) {
    const row = table.insertRow();
    row.append(Object.assign(document.createElement("th"), { textContent: String(p) }));
    for (const s of levels) {
      const td = row.insertCell();
      td.style.background = `rgb(${landscapeColour(8 * s, 8 * p, legend.max_level).join(",")})`;
      td.title = `sugar ${s}, spice ${p}`;
    }
  }
  els.legendCells.replaceChildren(legendTitle("Landscape: sugar and spice levels"), table,
    legendNote(`Scaled by the landscape's fixed capacity (${legend.max_level}); every level in eighths has its own ` +
      "shade. Hover for exact values."));
}

function updateHover() {
  const { frame, hover, legend } = state;
  const hit = frame && hover ? hitTest(frame, hover[0], hover[1]) : null;
  if (!hit) {
    els.hover.innerHTML = "<dt>–</dt><dd>Hover over the map.</dd>";
    return;
  }
  const rows = [["cell", `(${hit.cell.x}, ${hit.cell.y})`], ["cell sugar", hit.cell.sugar], ["cell spice", hit.cell.spice]];
  const a = hit.agent;
  if (a) {
    rows.push(
      ["agent", a.id], ["tribe", legend?.labels.tribe[a.tribe] ?? a.tribe], ["tags", a.tags, "tags"],
      ["tags set", a.ones], ["sugar", a.sugar], ["spice", a.spice], ["age", a.age], ["diseases", a.ndiseases],
      ["loans", `lender in ${a.lent}, borrower in ${a.owed}`],
    );
  } else {
    rows.push(["agent", "none"]);
  }
  els.hover.replaceChildren(...rows.flatMap(([k, v, cls]) => [
    Object.assign(document.createElement("dt"), { textContent: k }),
    Object.assign(document.createElement("dd"), { textContent: String(v), className: cls ?? "" }),
  ]));
}

function updateSettings() {
  const s = state.settings;
  els.settings.textContent = s
    ? `${s.exp} · raw seed ${s.seed}${state.runIndex != null ? ` (= run index ${state.runIndex})` : ""} · h ${s.h} · ` +
      `k ${s.k} · run ${state.run}`
    : "no run yet";
}

function updateStatus() {
  if (state.run === null) return;
  const n = state.newest;
  const text = {
    idle: `Started, not stepping: computed to t = ${n}.`,
    running: `Running: computed to t = ${n}.`,
    waiting: `Waiting: computed to t = ${n}, far enough ahead of the period shown; the model goes on when the map ` +
      "moves forward.",
    stopped: `Stopped at t = ${n}.`,
    extinct: `Extinct at t = ${n}: the population reached 0.`,
    failed: `Failed at t = ${n}: ${state.runError ?? "unknown error"}`,
  }[state.runState] ?? `${state.runState}: computed to t = ${n}.`;
  const kept = state.oldestKept !== null ? ` Kept for the map: t = ${state.oldestKept} to ${n}.` : "";
  els.status.textContent = text + kept;
}

function updateTimeControls() {
  const has = state.run !== null && state.newest >= 0;
  els.slider.min = String(state.oldestKept ?? 0);
  els.slider.max = String(Math.max(0, state.newest));
  if (state.frame) els.slider.value = String(state.frame.t);
  els.period.textContent = state.frame ? `t = ${state.frame.t}` : "t = –";
  els.captionT.textContent = state.frame ? String(state.frame.t) : "–";
  for (const el of [els.back, els.play, els.forward, els.slider]) el.disabled = !has;
  els.stop.disabled = state.run === null || TERMINAL.has(state.runState);
}

// --- the form -------------------------------------------------------------------------------------------------------

function fillFromExperiment() {
  const e = state.experiments.find((x) => x.id === els.experiment.value);
  if (!e) return;
  els.seed.value = String(e.seed);
  els.h.value = String(e.h);
  els.k.value = String(e.k);
  updateSeedNote();
}

function updateSeedNote() {
  const e = state.experiments.find((x) => x.id === els.experiment.value);
  const raw = Number(els.seed.value);
  const k = e && els.seed.value.trim() !== "" && Number.isInteger(raw) ? raw - e.seed : null;
  els.seedNote.textContent = k !== null && k >= 0 && k < e.seeds ? `= run index ${k}` : "";
}

async function init() {
  buildCharts();
  els.marksWhen.replaceChildren(...MARK_WHEN.map((o) => new Option(o.label, o.value)));
  els.marksWhich.replaceChildren(...MARK_WHICH.map((o) => new Option(o.label, o.value)));
  els.marksWhen.value = "now";
  els.marksWhich.value = "both";
  safely(render);
  try {
    state.experiments = await api("/api/experiments");
    els.experiment.replaceChildren(...state.experiments.map((e) => new Option(e.id, e.id)));
    const fallback = state.experiments[state.experiments.length - 1]?.id;
    els.experiment.value = state.experiments.some((e) => e.id === "VI-1-assim-k4") ? "VI-1-assim-k4" : fallback;
    fillFromExperiment();
  } catch (err) {
    showError(err);
  }
  loadLegend();

  els.experiment.addEventListener("change", fillFromExperiment);
  els.seed.addEventListener("input", updateSeedNote);
  els.form.addEventListener("submit", (event) => {
    event.preventDefault();
    startRun();
  });
  els.stop.addEventListener("click", stopRun);
  els.play.addEventListener("click", () => setPlaying(!state.playing));
  els.back.addEventListener("click", () => step(-1));
  els.forward.addEventListener("click", () => step(1));
  els.slider.addEventListener("input", () => {
    setPlaying(false);
    els.note.textContent = "";
    scrubTo(Number(els.slider.value));
  });
  // The marks menus: "this period" needs only the shown frame; "last 10 periods, fading" fetches the 9 before it.
  els.marksWhen.addEventListener("change", () => {
    els.marksWhich.disabled = els.marksWhen.value === "none";
    safely(drawLegend);
    const t = state.frame?.t;
    if (els.marksWhen.value === "fading" && t !== undefined) {
      showPeriod(t).then((shown) => {
        if (!shown && state.frame?.t === t) { // t is no longer kept: draw the marks of what the page has, with the note
          updateMarks();
          safely(render);
        }
      }).catch(reportUnlessStale);
    } else {
      state.recent = [];
      state.failed = [];
      updateMarks();
      safely(render);
    }
  });
  els.marksWhich.addEventListener("change", () => {
    safely(drawLegend);
    updateMarks();
    safely(drawMapNow);
  });
  els.colourBy.addEventListener("change", () => safely(() => {
    drawLegend();
    drawMapNow();
  }));

  const hoverAt = (cell) => {
    if (String(cell) === String(state.hover)) return;
    state.hover = cell;
    updateHover();
    safely(drawMapNow);
  };
  // Pointer events keep fractions of a CSS pixel, which matters at about one pixel a cell.
  els.map.addEventListener("pointermove", (event) => {
    if (!state.frame) return;
    const r = els.map.getBoundingClientRect();
    const { width: W, height: H } = state.frame;
    const x = Math.floor(((event.clientX - r.left) / r.width) * W);
    const row = Math.floor(((event.clientY - r.top) / r.height) * H);
    hoverAt(x >= 0 && x < W && row >= 0 && row < H ? [x, H - 1 - row] : null);
  });
  els.map.addEventListener("pointerleave", () => hoverAt(null));
  els.map.addEventListener("keydown", (event) => {
    const moves = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, 1], ArrowDown: [0, -1] };
    const move = moves[event.key];
    if (!move || !state.frame) return;
    event.preventDefault();
    const { width: W, height: H } = state.frame;
    const d = event.shiftKey ? 10 : 1;
    const [x, y] = state.hover ?? [Math.floor(W / 2), Math.floor(H / 2)];
    hoverAt([Math.min(W - 1, Math.max(0, x + move[0] * d)), Math.min(H - 1, Math.max(0, y + move[1] * d))]);
  });

  // Space plays or pauses, the left and right arrows step, unless a control or the map has the keyboard.
  document.addEventListener("keydown", (event) => {
    if (event.target.closest("input, select, textarea, button, canvas") || state.run === null) return;
    if (event.key === " ") {
      event.preventDefault();
      setPlaying(!state.playing);
    } else if (event.key === "ArrowLeft") {
      step(-1);
    } else if (event.key === "ArrowRight") {
      step(1);
    }
  });
  let resizeQueued = false;
  window.addEventListener("resize", () => {
    if (resizeQueued) return;
    resizeQueued = true;
    requestAnimationFrame(() => {
      resizeQueued = false;
      safely(render);
    });
  });
  pollStatus();
}

init();
