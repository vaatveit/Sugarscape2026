"""The experiment registry: each entry pairs a book label with its rules and parameters."""

import math
from dataclasses import dataclass

from sugarscape.config import Config


@dataclass(frozen=True)
class Experiment:
    id: str  # book label, e.g. "II-4"; sweep points use "II-5/m2/v5.5"
    title: str
    rules: str  # book notation, e.g. "({G1}, {M})"
    config: Config  # its seed is the base seed; run k uses base + k
    steps: int
    seeds: int


EXPERIMENTS: dict[str, Experiment] = {}


def register(exp: Experiment) -> Experiment:
    if exp.id in EXPERIMENTS:
        raise ValueError(f"experiment {exp.id} is already registered")
    EXPERIMENTS[exp.id] = exp
    return exp


register(
    Experiment(
        id="TEST-tiny",
        title="Tiny smoke experiment for runner tests",
        rules="({G1}, {M})",
        config=Config(initial_population=20),
        steps=5,
        seeds=2,
    )
)


# --- Chapter II: Life and Death on the Sugarscape ---------------------------------------

# Initial endowment for the Chapter II landscape runs. The book states none for II-1/II-2/II-6
# (only II-3's 5-25). Of the ranges the book uses elsewhere (5-25, 25-50 in Ch IV, 50-100 in
# Ch III), 25-50 reproduces Fig II-4's population curve: flat at 400 until t~7, ~255 at t~48
# (RMS error 11 agents vs 49 for 5-25 and 57 for 50-100, 5 seeds). See docs/book-notes.md.
CH2_ENDOWMENT = (25, 50)

register(Experiment(
    id="II-1",
    title="Immediate growback: agents stick to terrace ridges (Animation II-1, p.27)",
    rules="({G_inf}, {M})",
    config=Config(growback_rate=math.inf, endowment=CH2_ENDOWMENT),
    steps=100,
    seeds=5,
))

register(Experiment(
    id="II-4",
    title="Unit growback: carrying capacity 224 (Animation II-2, Figs II-4 and II-5 networks, pp.28-41)",
    rules="({G1}, {M})",
    config=Config(endowment=CH2_ENDOWMENT),
    steps=500,
    seeds=10,
))

# Fig II-5 (p.31): 500 agents; the book gives only mean vision and metabolism per point, so a
# mean of k is realized as the uniform range (1, 2k - 1) (our call).
FIG_II_5_VISION = {1: ("1", "2", "3", "5.5", "10.5"),
                   2: ("1", "2", "3", "5.5", "10.5"),
                   3: ("1", "2", "3", "4.5", "5.5", "6.5", "8", "10.5")}


def _mean_range(mean: float) -> tuple[int, int]:
    return (1, round(2 * mean - 1))


for _m, _visions in FIG_II_5_VISION.items():
    for _v in _visions:
        register(Experiment(
            id=f"II-5/m{_m}/v{_v}",
            title=f"Carrying capacity at mean metabolism {_m}, mean vision {_v} (Fig II-5, p.31)",
            rules="({G1}, {M})",
            config=Config(initial_population=500, metabolism=_mean_range(_m), vision=_mean_range(float(_v)),
                          endowment=CH2_ENDOWMENT),
            steps=500,
            seeds=10,
        ))

register(Experiment(
    id="II-4-gini",
    title="Wealth distribution and Gini with finite lives (Animations II-3 and II-4, pp.33-38)",
    rules="({G1}, {M, R[60,100]})",
    config=Config(initial_population=250, max_age=(60, 100), replacement=True),
    steps=500,
    seeds=10,
))

register(Experiment(
    id="II-6",
    title="Diagonal waves of migrators from a block start (Animation II-6, p.43)",
    rules="({G1}, {M})",
    # Block measured from Animation II-6 frame 1: 20 columns x 19 rows at the SW corner holding
    # ~284 agents (75% density), not 400 packed solid.
    config=Config(vision=(1, 10), placement="block", block=(0, 0, 20, 19), initial_population=284,
                  endowment=CH2_ENDOWMENT),
    steps=300,
    seeds=5,
))

register(Experiment(
    id="II-7",
    title="Seasonal migration and hibernation (Animation II-7, p.46)",
    rules="({S_1,8,50}, {M})",
    config=Config(seasons=(8, 50), endowment=CH2_ENDOWMENT),
    steps=500,
    seeds=5,
))

register(Experiment(
    id="II-8",
    title="Migration in a polluted environment (Animation II-8, p.49)",
    rules="({G1, D1}, {M, P11})",
    config=Config(pollution=(1.0, 1.0), pollution_start=50, diffusion_period=1, diffusion_start=100,
                  endowment=CH2_ENDOWMENT),
    steps=200,
    seeds=5,
))
