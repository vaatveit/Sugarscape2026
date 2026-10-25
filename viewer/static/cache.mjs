// Decoded periods kept in the page, so scrubbing back needs no refetch. One cache per run.
// No DOM access, so Node can import this module for tests/js/cache.test.mjs.

export const CACHE_LIMIT = 300;
// A decoded xl period measured 4.8 MB (VI-1, 20,000 agents) to 10.6 MB (III-12, 74,000), so the server's 100 kept
// periods could hold about 1 GB in the tab; refetching one from the local server takes about 0.1 s.
export const CACHE_LIMIT_XL = 20;

export class FrameCache {
  #frames = new Map(); // t -> decoded frame, in the order added
  #limit;

  constructor(xl) {
    this.#limit = xl ? CACHE_LIMIT_XL : CACHE_LIMIT;
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

  // Add a period, dropping the oldest added once over the limit.
  set(t, frame) {
    this.#frames.set(t, frame);
    if (this.#frames.size > this.#limit) this.#frames.delete(this.#frames.keys().next().value);
  }

  // Drop the periods the server no longer keeps.
  dropBefore(earliest) {
    for (const t of this.#frames.keys()) if (t < earliest) this.#frames.delete(t);
  }
}
