// Decoded frames kept in the page, so stepping back and drawing the marks of the last 10 periods need no refetch.
// One cache per run (adapted from viewer/static/cache.mjs). No DOM access.

// A frame of today's world is about 2.8 MB at 60,000 agents (38 bytes an agent plus 2 bytes a cell), so 30 frames hold
// about 85 MB: the shown period, its 9 predecessors for the marks, the frames fetched ahead while playing, and slack for
// scrubbing. Refetching one from the local server is quick.
export const CACHE_LIMIT = 30;

export class FrameCache {
  #frames = new Map(); // t -> decoded frame, in the order added
  #limit;

  constructor(limit = CACHE_LIMIT) {
    this.#limit = limit;
  }

  get size() {
    return this.#frames.size;
  }

  has(t) {
    return this.#frames.has(t);
  }

  get(t) {
    return this.#frames.get(t);
  }

  // Add a period, dropping the oldest added once over the limit (never the one just added).
  set(t, frame) {
    this.#frames.delete(t);
    this.#frames.set(t, frame);
    while (this.#frames.size > this.#limit) this.#frames.delete(this.#frames.keys().next().value);
  }

  // Drop the periods the server no longer keeps.
  dropBefore(earliest) {
    for (const t of [...this.#frames.keys()]) if (t < earliest) this.#frames.delete(t);
  }
}
