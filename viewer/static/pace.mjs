// Playback pacing between periods. No DOM access, so Node can import this module for tests/js/pace.test.mjs.

const channel = new MessageChannel();
const waiting = [];
channel.port1.onmessage = () => waiting.shift()?.();
channel.port1.unref?.(); // Node only: an open port would otherwise keep the test process alive

// A macrotask turn that needs no screen redraw. requestAnimationFrame never fires in a hidden page, which froze
// "max" playback, and background tabs hold timers to about one a second; messages are not held back.
function yieldTurn() {
  return new Promise((resolve) => {
    waiting.push(resolve);
    channel.port2.postMessage(null);
  });
}

// Wait out the rest of one period at `speed` periods per second ("max": no wait), given the time it already took.
export function pause(speed, elapsedMs) {
  const wait = speed === "max" ? 0 : 1000 / Number(speed) - elapsedMs;
  return wait > 0 ? new Promise((resolve) => setTimeout(resolve, wait)) : yieldTurn();
}
