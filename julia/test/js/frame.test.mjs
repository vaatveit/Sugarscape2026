// The page's frame decoder (julia/viewer/static/frame.mjs) against the fixture that Task 2's `frame encode layout` test
// writes: fixture-frame.bin holds the encoded bytes, fixture-frame.json the values they were built from.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import { decodeFrame } from "../../viewer/static/frame.mjs";

const here = new URL(".", import.meta.url);
const bytes = readFileSync(new URL("fixture-frame.bin", here));
const want = JSON.parse(readFileSync(new URL("fixture-frame.json", here), "utf8"));

// A fresh ArrayBuffer, as fetch's arrayBuffer() gives (a Node Buffer may sit at an offset in a shared pool).
const buffer = () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);

test("decodeFrame reads the fixture's header", () => {
  const f = decodeFrame(buffer());
  assert.equal(f.t, want.t);
  assert.equal(f.width, want.width);
  assert.equal(f.height, want.height);
  assert.equal(f.ntags, want.ntags);
  assert.equal(f.n, want.id.length);
});

test("decodeFrame reads every agent column, the events, the Lorenz curve, the Gini and the cells", () => {
  const f = decodeFrame(buffer());
  const columns = {
    sugar: "sugar", spice: "spice", id: "id", x: "x", y: "y", tags: "tags", age: "age", lent: "lender",
    owed: "borrower", tribe: "tribe", ones: "culture", wealth: "band", disease: "disease_step", role: "role",
    ndiseases: "diseases",
  };
  for (const [key, field] of Object.entries(columns)) {
    assert.deepEqual(Array.from(f.agents[key]), want[field], `agents.${key}`);
  }
  assert.deepEqual(Array.from(f.kills.x), want.kill_x);
  assert.deepEqual(Array.from(f.kills.y), want.kill_y);
  assert.deepEqual(Array.from(f.changes.x), want.change_x);
  assert.deepEqual(Array.from(f.changes.y), want.change_y);
  assert.deepEqual(Array.from(f.lorenz), want.lorenz);
  assert.equal(f.gini, want.gini);
  assert.deepEqual(Array.from(f.cellSugar8), want.cell_sugar);
  assert.deepEqual(Array.from(f.cellSpice8), want.cell_spice);
});

test("decodeFrame gives typed-array views on the buffer, not copies", () => {
  const ab = buffer();
  const f = decodeFrame(ab);
  for (const v of [f.agents.sugar, f.agents.id, f.agents.x, f.agents.tribe, f.lorenz, f.cellSugar8, f.kills.x]) {
    assert.equal(v.buffer, ab);
  }
  assert.ok(f.agents.sugar instanceof Float64Array);
  assert.ok(f.agents.id instanceof Uint32Array);
  assert.ok(f.agents.tags instanceof Uint16Array);
  assert.ok(f.agents.role instanceof Uint8Array);
});

test("decodeFrame refuses bytes that are not a frame", () => {
  const ab = buffer();
  new Uint8Array(ab)[0] = 0x41;
  assert.throws(() => decodeFrame(ab), /SXV1/);
  assert.throws(() => decodeFrame(buffer().slice(0, 40)), /length/);
});

test("a frame with no agents decodes, its Lorenz points and Gini undefined (NaN)", () => {
  // Header only, then 101 + 1 NaN Float64s and 3 x 2 cells of each resource: the layout of Task 2's empty frame.
  const cells = 3 * 2;
  const ab = new ArrayBuffer(32 + 102 * 8 + 2 * cells);
  const dv = new DataView(ab);
  new Uint8Array(ab).set([0x53, 0x58, 0x56, 0x31]);
  dv.setInt32(4, 3, true);
  dv.setUint16(8, 3, true);
  dv.setUint16(10, 2, true);
  dv.setUint8(24, 11);
  for (let i = 0; i < 102; i++) dv.setFloat64(32 + 8 * i, NaN, true);
  const f = decodeFrame(ab);
  assert.equal(f.n, 0);
  assert.equal(f.agents.sugar.length, 0);
  assert.equal(f.lorenz.length, 101);
  assert.ok(Array.from(f.lorenz).every(Number.isNaN));
  assert.ok(Number.isNaN(f.gini));
  assert.equal(f.cellSugar8.length, cells);
});
