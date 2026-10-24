"""One period of a run, copied out of the model exactly (viewer design: "never show anything the model didn't do").

A frame is the state after period t's rules have all run, the moment `Model.run`'s observer sees; t = 0 is the
initial placement. Grids are the landscape's `[x, y]` arrays raveled in C order, so cell (x, y) is index
`x * height + y`.
"""

from dataclasses import dataclass

import numpy as np

from sugarscape.model import Model

TRIBES = (None, "blue", "red")  # code + 1 -> value: -1 None, 0 blue, 1 red
SEXES = (None, "F", "M")


def _compact(a: np.ndarray) -> np.ndarray:
    """A copy of `a`, as float32 when that round-trips exactly (levels in eighths always do), else float64."""
    small = a.astype(np.float32)
    return small if np.array_equal(small, a) else a.astype(np.float64)


@dataclass(frozen=True, eq=False)
class Frame:
    t: int
    sugar: np.ndarray
    spice: np.ndarray | None  # None when the run has no spice
    id: np.ndarray
    x: np.ndarray
    y: np.ndarray
    vision: np.ndarray
    metabolism: np.ndarray
    age: np.ndarray
    sugar_held: np.ndarray
    spice_held: np.ndarray
    tribe: np.ndarray  # int8 codes, see TRIBES
    sex: np.ndarray  # int8 codes, see SEXES

    @property
    def population(self) -> int:
        return len(self.id)

    def to_json(self) -> dict:
        return {
            "t": self.t,
            "population": self.population,
            "sugar": self.sugar.astype(float).tolist(),
            "spice": None if self.spice is None else self.spice.astype(float).tolist(),
            "agents": {
                "id": self.id.tolist(),
                "x": self.x.tolist(),
                "y": self.y.tolist(),
                "sugar": self.sugar_held.tolist(),
                "spice": self.spice_held.tolist(),
                "tribe": [TRIBES[c + 1] for c in self.tribe.tolist()],
                "vision": self.vision.tolist(),
                "metabolism": self.metabolism.tolist(),
                "age": self.age.tolist(),
                "sex": [SEXES[c + 1] for c in self.sex.tolist()],
            },
        }


def capture(model: Model) -> Frame:
    agents, land = model.agents, model.landscape

    def column(get, dtype):
        return np.array([get(a) for a in agents], dtype=dtype)

    return Frame(
        t=model.t,
        sugar=_compact(land.sugar.ravel()),
        spice=_compact(land.spice.ravel()) if model.config.spice else None,
        id=column(lambda a: a.id, np.int64),
        x=column(lambda a: a.x, np.int16),
        y=column(lambda a: a.y, np.int16),
        vision=column(lambda a: a.vision, np.int32),
        metabolism=column(lambda a: a.metabolism, np.int32),
        age=column(lambda a: a.age, np.int64),
        sugar_held=column(lambda a: a.sugar, np.float64),
        spice_held=column(lambda a: a.spice, np.float64),
        tribe=column(lambda a: TRIBES.index(a.tribe) - 1, np.int8),
        sex=column(lambda a: SEXES.index(a.sex) - 1, np.int8),
    )
