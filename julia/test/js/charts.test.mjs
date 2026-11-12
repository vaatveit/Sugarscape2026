// The charts' line geometry (julia/viewer/static/charts.mjs): an undefined value (null in the series JSON, NaN in a
// frame's Lorenz curve) is a gap in the line, never a point at 0; the axes take every defined value and only those.
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  CHARTS, STUDY_END, chartCaption, chartsFor, linePath, markerPeriods, xMax, yTop,
} from "../../viewer/static/charts.mjs";

const xOf = (i) => 10 * i;
const yOf = (v) => 100 - 10 * v; // y of 0 is 100

test("linePath splits at null: [1, null, 2, 3] gives two segments", () => {
  const segments = linePath([1, null, 2, 3], xOf, yOf);
  assert.deepEqual(segments, [[[0, 90]], [[20, 80], [30, 70]]]);
});

test("no segment passes through y of 0 for the null", () => {
  for (const seg of linePath([1, null, 2, 3], xOf, yOf)) {
    for (const [x, y] of seg) {
      assert.notEqual(x, 10);
      assert.notEqual(y, yOf(0));
    }
  }
});

test("NaN and undefined are gaps too; leading, trailing and repeated gaps give no empty segment", () => {
  assert.deepEqual(linePath([null, NaN, 4, undefined, null, 5, null], xOf, yOf), [[[20, 60]], [[50, 50]]]);
  assert.deepEqual(linePath([], xOf, yOf), []);
  assert.deepEqual(linePath([null, null], xOf, yOf), []);
  assert.deepEqual(linePath(new Float64Array([0, NaN, 0.5]), xOf, yOf), [[[0, 100]], [[20, 95]]]); // a real 0 is drawn
});

test("yTop covers the largest defined value and ignores the undefined ones", () => {
  assert.equal(yTop([[null, 3, 7], [NaN, 2]]), 10);
  assert.equal(yTop([[null, null]]), 1);
  assert.equal(yTop([[0, 0]]), 1);
  assert.equal(yTop([[0.3]]), 0.5);
  assert.equal(yTop([[12000]]), 20000);
});

test("xMax: periods 0 to newest on a nice scale that reaches 500 (the study's end) once the run gets there", () => {
  assert.equal(xMax(0), 10);
  assert.equal(xMax(10), 10);
  assert.equal(xMax(11), 20);
  assert.equal(xMax(130), 200);
  assert.equal(xMax(499), 500);
  assert.equal(xMax(501), 1000);
});

test("the eleven charts of the specs draw the server's series keys", () => {
  assert.equal(CHARTS.length, 11);
  const keys = CHARTS.flatMap((c) => c.panels.flatMap((p) => p.lines.map((l) => l.key)));
  assert.deepEqual(keys.sort(), [
    "agent_pollution", "agents_other", "agents_rich", "fraction_sick", "gini", "killed_blue", "killed_red",
    "mean_pollution", "mean_price", "n_blue", "n_loans", "n_red", "pollution_other", "pollution_rich", "share_rich",
    "total_debt", "trades", "tribe_changes",
  ]);
});

// A legend's pollution entry as julia/viewer/encoding.jl's `pollution_legend` gives it for VI-1-pollution.
const pollution = {
  palette: Array(9).fill("#ffffff"), labels: Array(9).fill(""), edges: [1, 3, 10, 30, 100, 300, 1000], start: 350,
  diffusion_start: 450, rich_cut: 5, rich_share: 0.3218, decay: 0,
};

test("the two pollution charts come after the seven, are shown only with pollution, and draw what the spec says", () => {
  const [p, r] = CHARTS.slice(-4, -2);
  assert.equal(p.id, "pollution");
  assert.equal(p.title, "Pollution");
  assert.equal(p.when, "pollution");
  assert.deepEqual(p.panels.map((q) => q.lines.map((l) => [l.key, l.label])),
    [[["mean_pollution", "whole world"], ["agent_pollution", "where agents stand"]]]);
  assert.equal(p.panels[0].lines[0].colour, "#6b7280");
  assert.equal(r.id, "rich");
  assert.equal(r.title, "On the richest land");
  assert.equal(r.when, "pollution");
  assert.equal(r.panels.length, 1);
  assert.equal(r.panels[0].fixed, 1);
  assert.deepEqual(r.panels[0].lines.map((l) => l.key), ["share_rich"]);
  assert.ok(CHARTS.slice(0, -4).every((c) => c.when === undefined));
});

test("chartsFor: the charts a run's legend has series for", () => {
  assert.deepEqual(chartsFor(null).map((c) => c.id), CHARTS.slice(0, 7).map((c) => c.id));
  assert.deepEqual(chartsFor({ pollution: null }).map((c) => c.id), CHARTS.slice(0, 7).map((c) => c.id));
  assert.deepEqual(chartsFor({ pollution }).map((c) => c.id), CHARTS.map((c) => c.id));
});

test("chartCaption: the richest land's cut and the share of the world it covers, from the legend", () => {
  const rich = CHARTS.find((c) => c.id === "rich");
  assert.equal(chartCaption(rich, { pollution }), "cells with sugar + spice capacity ≥ 5: 32.2% of the world");
  assert.equal(chartCaption(rich, { pollution: null }), "");
  assert.equal(chartCaption(rich, null), "");
  for (const c of CHARTS.filter((c) => c.id !== "rich")) assert.equal(chartCaption(c, { pollution }), "");
});

test("markerPeriods: the study's end from the run's steps, 500 without them", () => {
  assert.equal(STUDY_END, 500);
  assert.deepEqual(markerPeriods({}), [{ t: 500, kind: "study-end", label: null }]);
  assert.deepEqual(markerPeriods({ studyEnd: 500, legend: { pollution: null } }),
    [{ t: 500, kind: "study-end", label: null }]);
  assert.deepEqual(markerPeriods({ studyEnd: 600, legend: null }), [{ t: 600, kind: "study-end", label: null }]);
});

test("markerPeriods: the starts of pollution and diffusion from the legend, none at 0 or absent", () => {
  assert.deepEqual(markerPeriods({ studyEnd: 600, legend: { pollution } }), [
    { t: 600, kind: "study-end", label: null },
    { t: 350, kind: "pollution", label: "pollution on" },
    { t: 450, kind: "diffusion", label: "diffusion on" },
  ]);
  const t0 = { ...pollution, start: 0, diffusion_start: 0 }; // VI-1-pollution-t0: no marker
  assert.deepEqual(markerPeriods({ studyEnd: 600, legend: { pollution: t0 } }),
    [{ t: 600, kind: "study-end", label: null }]);
  const noDiffusion = { ...pollution, diffusion_start: null };
  assert.deepEqual(markerPeriods({ studyEnd: 600, legend: { pollution: noDiffusion } }), [
    { t: 600, kind: "study-end", label: null }, { t: 350, kind: "pollution", label: "pollution on" },
  ]);
});

// docs/superpowers/specs/2026-11-11-pollution-decay-design.md, "The viewer".
test("the two decay charts come last: agents on and off rich land, pollution on rich land and elsewhere", () => {
  const [a, q] = CHARTS.slice(-2);
  assert.equal(a.id, "rich_count");
  assert.equal(a.title, "Agents on rich land");
  assert.equal(a.when, "pollution");
  assert.deepEqual(a.panels.map((p) => p.lines.map((l) => [l.key, l.label])),
    [[["agents_rich", "on rich land"], ["agents_other", "elsewhere"]]]);
  assert.equal(a.panels[0].fixed, undefined); // a count, on its own axis
  assert.equal(q.id, "rich_pollution");
  assert.equal(q.title, "Pollution on rich land and elsewhere");
  assert.equal(q.when, "pollution");
  assert.deepEqual(q.panels.map((p) => p.lines.map((l) => l.key)), [["pollution_rich", "pollution_other"]]);
  const ids = (legend) => chartsFor(legend).map((c) => c.id);
  assert.ok(ids({ pollution }).includes("rich_count") && ids({ pollution }).includes("rich_pollution"));
  assert.ok(!ids({ pollution: null }).includes("rich_count") && !ids({ pollution: null }).includes("rich_pollution"));
});

test("markerPeriods: the pollution marker names the decay when there is one", () => {
  const decaying = { ...pollution, decay: 0.045 };
  assert.deepEqual(markerPeriods({ studyEnd: 1000, legend: { pollution: decaying } }), [
    { t: 1000, kind: "study-end", label: null },
    { t: 350, kind: "pollution", label: "pollution on, decays 4.5%" },
    { t: 450, kind: "diffusion", label: "diffusion on" },
  ]);
  const t0 = { ...decaying, start: 0, diffusion_start: 0 }; // decay from the first period: no marker
  assert.deepEqual(markerPeriods({ studyEnd: 1000, legend: { pollution: t0 } }),
    [{ t: 1000, kind: "study-end", label: null }]);
});
