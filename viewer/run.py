"""One run of a registered experiment, stepped on demand and recorded period by period."""

import threading
import uuid
from collections import deque
from dataclasses import replace

from experiments.registry import EXPERIMENTS
from sugarscape.config import Config
from sugarscape.model import Model
from sugarscape.xl import to_xl
from viewer.frames import Frame, capture

LEAD = 50  # furthest a request may reach past the latest computed period
KEEP = 500  # periods kept for scrubbing, the newest ones (user decision 2026-10-24); about 25 KB each
KEEP_XL = 100  # the same for xl runs, whose frames are about 2.5 MB each (xl design)


class OutOfRange(ValueError):
    """A period the run can't serve yet; kept apart from any ValueError the model itself raises."""


class NotKept(OutOfRange):
    """A period that was computed but has since dropped out of the run's window of kept periods."""


class RunBroken(RuntimeError):
    """The model raised during a step. It may be half-updated, so the run computes nothing further."""


def catalog() -> list[dict]:
    """Experiments on the sugar/spice grid (Schelling and Ring World excluded), the book's first, then VAR-."""
    grid = [e for i, e in EXPERIMENTS.items() if isinstance(e.config, Config) and i != "TEST-tiny"]
    grid.sort(key=lambda e: e.id.startswith("VAR-"))  # stable: registry order within each group
    return [{"id": e.id, "title": e.title, "steps": e.steps, "seeds": e.seeds} for e in grid]


class Run:
    """Run k of an experiment (or its xl version), seeded as experiments/run.py seeds it (base seed + k)."""

    def __init__(self, exp_id: str, seed_index: int, xl: bool = False) -> None:
        exp = EXPERIMENTS.get(exp_id)
        if exp is None or exp_id == "TEST-tiny" or not isinstance(exp.config, Config):
            raise ValueError(f"no grid experiment {exp_id!r}")
        if isinstance(seed_index, bool) or not isinstance(seed_index, int) or seed_index < 0:
            raise ValueError(f"seed must be an integer >= 0, not {seed_index!r}")
        self.id = uuid.uuid4().hex  # requests name it, so a replaced run's page can't be fed another run's frames
        self.experiment, self.seed_index = exp, seed_index
        self.seed = exp.config.seed + seed_index
        self.xl = xl
        self.keep = KEEP_XL if xl else KEEP
        self.model = Model(replace(to_xl(exp.config) if xl else exp.config, seed=self.seed))
        first = capture(self.model)
        self._frames: deque[Frame] = deque([first], maxlen=self.keep)  # the newest periods
        self._populations: list[int] = [first.population]  # every period, for the chart
        self._step_lock = threading.Lock()  # one stepper at a time
        self._lock = threading.Lock()  # guards the window and series; held only briefly, never across a step
        self.error: Exception | None = None  # set when a step raised; periods before it still serve

    @property
    def latest(self) -> int:
        return len(self._populations) - 1

    @property
    def earliest(self) -> int:
        """Oldest period still kept."""
        return self.latest - len(self._frames) + 1

    def frame(self, t: int) -> Frame:
        """The state after period t, stepping the model up to t first if it hasn't got there.

        A period already computed is served without waiting for a step in progress (scrubbing stays immediate).
        """
        kept = self._kept(t)
        if kept is not None:
            return kept
        with self._step_lock:
            with self._lock:
                if t > self.latest + LEAD:
                    raise OutOfRange(f"t={t} is outside 0..{self.latest + LEAD}")
                if t > self.latest and self.error is not None:
                    raise RunBroken(f"the run stopped at t={self.latest + 1}: {self.error}") from self.error
            while self.latest < t:
                try:
                    self.model.step()
                except Exception as e:
                    self.error = e
                    raise
                frame = capture(self.model)
                with self._lock:
                    self._frames.append(frame)
                    self._populations.append(frame.population)
        return self._kept(t)

    def _kept(self, t: int) -> Frame | None:
        """Period t if it is in the window; None if not computed yet; raises if it is out of reach."""
        with self._lock:
            if t < 0:
                raise OutOfRange(f"t={t} is outside 0..{self.latest + LEAD}")
            if t < self.earliest:
                raise NotKept(f"t={t} is no longer kept: only the last {self.keep} periods are ({self.earliest}..{self.latest})")
            return self._frames[t - self.earliest] if t <= self.latest else None

    def populations(self, start: int = 0) -> list[int]:
        with self._lock:
            return self._populations[start:]

    def info(self) -> dict:
        exp, cfg, land = self.experiment, self.model.config, self.model.landscape
        return {
            "run": self.id,
            "experiment": exp.id,
            "title": exp.title,
            "rules": exp.rules,
            "steps": exp.steps,
            "seeds": exp.seeds,
            "seed_index": self.seed_index,
            "seed": self.seed,
            "xl": self.xl,
            "keep": self.keep,
            "width": land.width,
            "height": land.height,
            "tribes": bool(cfg.tag_length),
            "spice": bool(cfg.spice),
            "sugar_capacity": land.capacity.ravel().tolist(),
            "spice_capacity": land.spice_capacity.ravel().tolist() if cfg.spice else None,
            "sugar_max": int(land.capacity.max()),
            "spice_max": int(land.spice_capacity.max()) if cfg.spice else 0,
        }
