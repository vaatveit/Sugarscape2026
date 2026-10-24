"""One run of a registered experiment, stepped on demand and recorded period by period."""

import threading
import uuid
from dataclasses import replace

from experiments.registry import EXPERIMENTS
from sugarscape.config import Config
from sugarscape.model import Model
from viewer.frames import Frame, capture

LEAD = 50  # furthest a request may reach past the latest computed period


class OutOfRange(ValueError):
    """A period the run can't serve yet; kept apart from any ValueError the model itself raises."""


class RunBroken(RuntimeError):
    """The model raised during a step. It may be half-updated, so the run computes nothing further."""


def catalog() -> list[dict]:
    """Experiments on the sugar/spice grid (Schelling and Ring World excluded), the book's first, then VAR-."""
    grid = [e for i, e in EXPERIMENTS.items() if isinstance(e.config, Config) and i != "TEST-tiny"]
    grid.sort(key=lambda e: e.id.startswith("VAR-"))  # stable: registry order within each group
    return [{"id": e.id, "title": e.title, "steps": e.steps, "seeds": e.seeds} for e in grid]


class Run:
    """Run k of an experiment, seeded as experiments/run.py seeds it (base seed + k)."""

    def __init__(self, exp_id: str, seed_index: int) -> None:
        exp = EXPERIMENTS.get(exp_id)
        if exp is None or exp_id == "TEST-tiny" or not isinstance(exp.config, Config):
            raise ValueError(f"no grid experiment {exp_id!r}")
        if isinstance(seed_index, bool) or not isinstance(seed_index, int) or seed_index < 0:
            raise ValueError(f"seed must be an integer >= 0, not {seed_index!r}")
        self.id = uuid.uuid4().hex  # requests name it, so a replaced run's page can't be fed another run's frames
        self.experiment, self.seed_index = exp, seed_index
        self.seed = exp.config.seed + seed_index
        self.model = Model(replace(exp.config, seed=self.seed))
        self._frames: list[Frame] = [capture(self.model)]
        self._lock = threading.Lock()
        self.error: Exception | None = None  # set when a step raised; periods before it still serve

    @property
    def latest(self) -> int:
        return len(self._frames) - 1

    def frame(self, t: int) -> Frame:
        """The state after period t, stepping the model up to t first if it hasn't got there."""
        with self._lock:
            if t < 0 or t > self.latest + LEAD:
                raise OutOfRange(f"t={t} is outside 0..{self.latest + LEAD}")
            if t > self.latest and self.error is not None:
                raise RunBroken(f"the run stopped at t={self.latest + 1}: {self.error}") from self.error
            while self.latest < t:
                try:
                    self.model.step()
                except Exception as e:
                    self.error = e
                    raise
                self._frames.append(capture(self.model))
            return self._frames[t]

    def populations(self, start: int = 0) -> list[int]:
        with self._lock:
            return [f.population for f in self._frames[start:]]

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
            "width": land.width,
            "height": land.height,
            "tribes": bool(cfg.tag_length),
            "spice": bool(cfg.spice),
            "sugar_capacity": land.capacity.ravel().tolist(),
            "spice_capacity": land.spice_capacity.ravel().tolist() if cfg.spice else None,
            "sugar_max": int(land.capacity.max()),
            "spice_max": int(land.spice_capacity.max()) if cfg.spice else 0,
        }
