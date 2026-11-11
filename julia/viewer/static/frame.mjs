// Decodes one period's frame as julia/viewer/frame.jl's `encode_frame` writes it. No DOM access, so Node can import this
// module for julia/test/js/frame.test.mjs.
//
// Layout (little-endian; each section starts at a multiple of its element size, so every column is a typed-array view
// on the response's buffer, never a copy):
//   header, 32 bytes: "SXV1", t Int32, width and height UInt16, n_agents, n_kills, n_changes UInt32, ntags UInt8, 7 zeros
//   Float64: agent sugar (n), agent spice (n), Lorenz curve (101), Gini (1)
//   UInt32:  agent id (n)
//   UInt16:  agent x, y, tags, age, loans as lender, loans as borrower (n each); kill x, kill y; change x, change y
//   UInt8:   agent tribe, culture ones, wealth band, disease step, credit role, disease count (n each);
//            cell sugar eighths, cell spice eighths (width * height each, index y * width + x)

const MAGIC = "SXV1";
const HEADER_BYTES = 32;
const LORENZ_POINTS = 101;

// Typed arrays read in the platform's byte order; the frame is little-endian, as every platform a browser runs on.
const LITTLE_ENDIAN = new Uint8Array(new Uint16Array([1]).buffer)[0] === 1;

/**
 * decodeFrame(arrayBuffer) -> {t, width, height, ntags, n, agents: {...}, kills: {x, y}, changes: {x, y}, lorenz, gini,
 * cellSugar8, cellSpice8}. Agent columns: sugar, spice, id, x, y, tags, age, lent (active loans as lender), owed (as
 * borrower), tribe (0 blue, 1 red), ones (tags set), wealth (band), disease (step), role (credit), ndiseases (count).
 * A Gini or Lorenz point the model leaves undefined is NaN.
 */
export function decodeFrame(buffer) {
  if (!LITTLE_ENDIAN) throw new Error("this page reads frames on little-endian platforms only");
  if (buffer.byteLength < HEADER_BYTES) throw new Error(`a frame is at least ${HEADER_BYTES} bytes, not length ${buffer.byteLength}`);
  const dv = new DataView(buffer);
  const magic = String.fromCharCode(...new Uint8Array(buffer, 0, 4));
  if (magic !== MAGIC) throw new Error(`not a frame: it starts with ${JSON.stringify(magic)}, not ${MAGIC}`);
  const t = dv.getInt32(4, true);
  const width = dv.getUint16(8, true);
  const height = dv.getUint16(10, true);
  const n = dv.getUint32(12, true);
  const nk = dv.getUint32(16, true);
  const nc = dv.getUint32(20, true);
  const ntags = dv.getUint8(24);
  const cells = width * height;
  const expected = HEADER_BYTES + 8 * (2 * n + LORENZ_POINTS + 1) + 4 * n + 2 * (6 * n + 2 * nk + 2 * nc) + 6 * n +
    2 * cells;
  if (buffer.byteLength !== expected) {
    throw new Error(`a frame of ${n} agents, ${nk} kills, ${nc} changes and ${cells} cells has length ${expected}, ` +
      `not ${buffer.byteLength}`);
  }

  let offset = HEADER_BYTES;
  const take = (Type, count) => {
    const view = new Type(buffer, offset, count);
    offset += count * Type.BYTES_PER_ELEMENT;
    return view;
  };
  const sugar = take(Float64Array, n);
  const spice = take(Float64Array, n);
  const lorenz = take(Float64Array, LORENZ_POINTS);
  const gini = take(Float64Array, 1)[0];
  const id = take(Uint32Array, n);
  const x = take(Uint16Array, n);
  const y = take(Uint16Array, n);
  const tags = take(Uint16Array, n);
  const age = take(Uint16Array, n);
  const lent = take(Uint16Array, n);
  const owed = take(Uint16Array, n);
  const kills = { x: take(Uint16Array, nk), y: take(Uint16Array, nk) };
  const changes = { x: take(Uint16Array, nc), y: take(Uint16Array, nc) };
  const tribe = take(Uint8Array, n);
  const ones = take(Uint8Array, n);
  const wealth = take(Uint8Array, n);
  const disease = take(Uint8Array, n);
  const role = take(Uint8Array, n);
  const ndiseases = take(Uint8Array, n);
  const cellSugar8 = take(Uint8Array, cells);
  const cellSpice8 = take(Uint8Array, cells);
  return {
    t, width, height, ntags, n,
    agents: { sugar, spice, id, x, y, tags, age, lent, owed, tribe, ones, wealth, disease, role, ndiseases },
    kills, changes, lorenz, gini, cellSugar8, cellSpice8,
  };
}
