import { test } from "node:test";
import assert from "node:assert/strict";

import { boardPixels, paintCells } from "../../viewer/static/board.mjs";
import { COLOR_MODES, PALETTES, cellColor } from "../../viewer/static/encoding.mjs";

const hexRgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));

test("the board is a whole number of device pixels per cell, never less than one", () => {
  assert.equal(boardPixels(960, 500), 500); // 640 CSS px at devicePixelRatio 1.5
  assert.equal(boardPixels(1000, 500), 1000);
  assert.equal(boardPixels(1499, 500), 1000);
  assert.equal(boardPixels(300, 500), 500); // a small window scrolls instead of dropping rows
  assert.equal(boardPixels(640, 50), 600); // regular boards keep whole pixels per cell too
});

// A 3 x 2 world: cell (x, y) is index x * 2 + y; agents at (0, 1) and (2, 0).
const info = { width: 3, height: 2, sugar_max: 4, spice_max: 4 };
const agents = [
  { x: 0, y: 1, tribe: "red", sugar: 1, spice: 0 },
  { x: 2, y: 0, tribe: "blue", sugar: 1, spice: 0 },
];
const frame = {
  sugar: [0, 0.5, 1, 2, 3.125, 4],
  spice: [4, 3, 2, 1, 0.5, 0],
  agents,
  at: new Map(agents.map((a) => [a.x * 2 + a.y, a])),
};

function pixel(image, px, py) {
  const k = (py * info.width + px) * 4;
  return Array.from(image.slice(k, k + 4));
}

test("every pixel is its cell's color, or its agent's, with north at the top", () => {
  const palette = PALETTES.xl;
  const image = paintCells(frame, info, COLOR_MODES.tribe, palette);
  assert.equal(image.length, 3 * 2 * 4);
  for (let x = 0; x < 3; x++) {
    for (let y = 0; y < 2; y++) {
      const i = x * 2 + y;
      const agent = frame.at.get(i);
      const rgb = agent
        ? hexRgb(COLOR_MODES.tribe.color(agent, palette))
        : cellColor(frame.sugar[i], frame.spice[i], 4, 4, palette.weight);
      assert.deepEqual(pixel(image, x, 1 - y), [...rgb, 255], `cell (${x}, ${y})`);
    }
  }
  assert.deepEqual(pixel(image, 0, 0), [...hexRgb(palette.tribe.red), 255]); // (0, 1) is the top row
});

test("sugar-only runs paint without a spice term", () => {
  const image = paintCells({ ...frame, spice: null, agents: [], at: new Map() }, { ...info, spice_max: 0 },
    COLOR_MODES.none, PALETTES.xl);
  assert.deepEqual(pixel(image, 2, 1), [...cellColor(3.125, 0, 4, 0, PALETTES.xl.weight), 255]); // cell (2, 0)
});

test("the image holds no color that is neither a cell's nor an agent's", () => {
  const palette = PALETTES.xl;
  const image = paintCells(frame, info, COLOR_MODES.wealth, palette);
  const allowed = new Set([
    ...frame.sugar.map((s, i) => cellColor(s, frame.spice[i], 4, 4, palette.weight).join()),
    ...agents.map((a) => hexRgb(COLOR_MODES.wealth.color(a, palette)).join()),
  ]);
  for (let k = 0; k < image.length; k += 4) {
    assert.ok(allowed.has(Array.from(image.slice(k, k + 3)).join()), `pixel ${k / 4}`);
    assert.equal(image[k + 3], 255);
  }
});
