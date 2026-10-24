// The population count of every period of a run, for the chart. Runs have no length cap, so nothing here spreads
// the series into a call (Math.max(...a) and push(...a) overflow the stack from about 150,000 periods).
// No DOM access, so Node can import this module for tests/js/series.test.mjs.

export class PopulationSeries {
  #counts = [];
  #max = 0;

  get length() {
    return this.#counts.length;
  }

  // Largest count so far (0 for an empty series), kept as counts arrive.
  get max() {
    return this.#max;
  }

  at(t) {
    return this.#counts[t];
  }

  // Add counts for periods from, from + 1, ...; only a chunk that continues the series is taken.
  append(from, counts) {
    if (from !== this.#counts.length) return false;
    for (const n of counts) {
      this.#counts.push(n);
      if (n > this.#max) this.#max = n;
    }
    return true;
  }
}
