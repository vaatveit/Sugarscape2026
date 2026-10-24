// Board geometry and the one-pixel-per-cell painting used for xl runs. No DOM access, so Node can import this module
// for tests/js/board.test.mjs. Every color comes from encoding.mjs.
import { cellColor } from "./encoding.mjs";

// Device pixels for a board `cells` wide given `available` device pixels: a whole number per cell, at least one. A
// board that doesn't fit stays this size and the page scrolls, so no row or column is dropped (xl design).
export function boardPixels(available, cells) {
  return Math.max(cells, Math.floor(available / cells) * cells);
}

function rgbOf(color) {
  return [1, 3, 5].map((i) => parseInt(color.slice(i, i + 2), 16));
}

// RGBA for a width x height image, one pixel per cell, north at the top: each cell's own color, or where an agent
// stands, the agent's color from `colorMode` in `palette`. Nothing is blended.
export function paintCells(frame, info, colorMode, palette) {
  const { width: W, height: H } = info;
  const image = new Uint8ClampedArray(W * H * 4);
  const put = (x, y, rgb) => {
    const k = ((H - 1 - y) * W + x) * 4;
    image[k] = rgb[0];
    image[k + 1] = rgb[1];
    image[k + 2] = rgb[2];
    image[k + 3] = 255;
  };
  for (let x = 0; x < W; x++) {
    for (let y = 0; y < H; y++) {
      const i = x * H + y;
      put(x, y, cellColor(frame.sugar[i], frame.spice ? frame.spice[i] : 0, info.sugar_max, info.spice_max,
        palette.weight));
    }
  }
  const colors = new Map(); // agent colors repeat; parse each once
  for (const agent of frame.agents) {
    const color = colorMode.color(agent, palette);
    if (!colors.has(color)) colors.set(color, rgbOf(color));
    put(agent.x, agent.y, colors.get(color));
  }
  return image;
}
