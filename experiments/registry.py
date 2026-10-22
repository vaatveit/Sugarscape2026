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
    # p.42: "In all other respects the agents and sugarscape are exactly as in animation II-2",
    # so 400 agents; the 20x20 SW block is our reading of frame 1.
    config=Config(vision=(1, 10), placement="block", block=(0, 0, 20, 20), endowment=CH2_ENDOWMENT),
    steps=300,
    seeds=5,
))

register(Experiment(
    id="II-6-measured",
    title="II-6 with the block measured from Animation II-6 frame 1 (variant)",
    rules="({G1}, {M})",
    # Blob count of frame 1: 20 columns x 19 rows at the SW corner holding ~284 agents (75%).
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


# --- Chapter III: Sex, Culture, and Conflict ---------------------------------------------

# p.57: childbearing from 12-15; ends 40-50 (women), 50-60 (men); natural death 60-100;
# initial endowments 50-100.
CH3_SEX = dict(sex=True, max_age=(60, 100), endowment=(50, 100))
TAGS = 11  # p.74
BLUE_BLOCK, RED_BLOCK = (0, 0, 20, 20), (30, 30, 20, 20)  # Animations III-9, III-12 frame 1


def _blocks(n: int) -> tuple[tuple[str, int, int, int, int, int], ...]:
    """Blue block SW, Red block NE, n agents each (densities measured from frame 1; our call)."""
    return (("blue", *BLUE_BLOCK, n), ("red", *RED_BLOCK, n))


register(Experiment(
    id="III-1", title="Sexual reproduction: steady population and evolution (Figs III-1, III-2)",
    rules="({G1}, {M, S})", config=Config(**CH3_SEX), steps=2500, seeds=5))
register(Experiment(
    id="III-3", title="Small oscillations: fertility ends 10 years earlier (Fig III-3, p.64)",
    rules="({G1}, {M, S})",
    config=Config(**CH3_SEX, female_fertility_end=(30, 40), male_fertility_end=(40, 50)),
    steps=2500, seeds=5))
register(Experiment(
    id="III-4", title="Large oscillations: reproduction needs 10-40 sugar (Fig III-4, p.65)",
    rules="({G1}, {M, S})", config=Config(**{**CH3_SEX, "endowment": (10, 40)}), steps=2500, seeds=5))
register(Experiment(
    id="III-5", title="Extinction: both changes combined (Fig III-5, p.66)",
    rules="({G1}, {M, S})",
    config=Config(**{**CH3_SEX, "endowment": (10, 40)}, female_fertility_end=(30, 40), male_fertility_end=(40, 50)),
    steps=1500, seeds=10))
register(Experiment(
    id="III-7", title="Inheritance retards selection, raises inequality (Fig III-7, p.67)",
    rules="({G1}, {M, S, I})", config=Config(**CH3_SEX, inheritance=True), steps=1000, seeds=5))
register(Experiment(
    id="III-8", title="Cultural transmission: tribes converge (Animation III-6, Fig III-8, p.74)",
    rules="({G1}, {M, K})", config=Config(tag_length=TAGS, culture=True, endowment=CH2_ENDOWMENT),
    # Run to absorption: each side "will ultimately converge" (p.74, fn 22); the book's run took ~2700.
    steps=6000, seeds=5))
register(Experiment(
    id="III-9", title="Combat, reward = victim's wealth (Animations III-9, III-10, p.83)",
    rules="({G1}, {C_inf})",
    config=Config(tag_length=TAGS, combat_alpha=math.inf, endowment=CH2_ENDOWMENT, initial_blocks=_blocks(270)),
    steps=1000, seeds=10))
register(Experiment(
    id="III-11", title="Combat C2 with same-tribe replacement: war of attrition (Animation III-11, p.86)",
    rules="({G1}, {C2, R[60,100]})",
    config=Config(tag_length=TAGS, combat_alpha=2, endowment=CH2_ENDOWMENT, max_age=(60, 100), replacement=True,
                  replacement_same_tribe=True, initial_blocks=_blocks(200)),
    steps=1000, seeds=5))
register(Experiment(
    id="III-12", title="Colliding waves, no combat (Animation III-12, p.86)",
    rules="({G1}, {M})",
    config=Config(tag_length=TAGS, vision=(1, 10), endowment=CH2_ENDOWMENT, initial_blocks=_blocks(370)),
    steps=200, seeds=5))
register(Experiment(
    id="III-13", title="Combat C2 suppresses the waves (Animation III-13, p.86)",
    rules="({G1}, {C2})",
    config=Config(tag_length=TAGS, vision=(1, 10), combat_alpha=2, endowment=CH2_ENDOWMENT,
                  initial_blocks=_blocks(370)),
    steps=200, seeds=5))
register(Experiment(
    id="III-14", title="Combat and assimilation (Animation III-14, p.90)",
    rules="({G1}, {C_inf, K})",
    config=Config(tag_length=TAGS, combat_alpha=math.inf, culture=True, endowment=CH2_ENDOWMENT,
                  initial_blocks=_blocks(270)),
    steps=1000, seeds=10))
register(Experiment(
    id="III-15", title="Proto-history (Animation III-15, p.92)",
    rules="({G1}, {M, S, K})",
    # "A small, low density, primordial soup": 100 agents (our call).
    config=Config(**CH3_SEX, initial_population=100, tag_length=TAGS, culture=True),
    steps=6000, seeds=20))  # fn 32's frequencies are eventual outcomes: run to absorption


# --- Chapter IV: Sugar and Spice ------------------------------------------------------------

# p.108: 200 infinitely lived agents; metabolisms U[1,5] for each good; vision U[1,5];
# endowments U[25,50] for both goods.
NEO = dict(spice=True, trade=True, metabolism=(1, 5), spice_metabolism=(1, 5), vision=(1, 5),
           endowment=(25, 50), initial_population=200)
# p.123 (Fig IV-14): puberty 12-15; childbearing ends 35-45 (women), 45-55 (men); death 60-100.
CH4_SEX = dict(sex=True, fertility_start=(12, 15), female_fertility_end=(35, 45), male_fertility_end=(45, 55),
               max_age=(60, 100))
VISION_CAP = 24  # vision must stay below half the 50-site grid


def _vision_for_mean(mean: float) -> tuple[int, int]:
    """Mean k as (1, 2k - 1), shifted to (2k - 24, 24) above the vision cap (our call)."""
    high = round(2 * mean - 1)
    return (1, high) if high <= VISION_CAP else (round(2 * mean) - VISION_CAP, VISION_CAP)


register(Experiment(
    id="IV-3", title="Neoclassical agents: price convergence (Figs IV-3 to IV-5, p.108)",
    rules="({G1}, {M, T})", config=Config(**NEO), steps=1000, seeds=10))

for _trade in (True, False):
    for _v in (1, 2, 3, 6, 10):
        register(Experiment(
            id=f"IV-6/{'trade' if _trade else 'notrade'}/v{_v:g}",
            title=f"Carrying capacity {'with' if _trade else 'without'} trade, mean vision {_v} (Fig IV-6, p.112)",
            rules="({G1}, {M, T})" if _trade else "({G1}, {M})",
            # 400 starters (book silent): the asymptote is approached from above.
            config=Config(**{**NEO, "trade": _trade, "initial_population": 400, "vision": _vision_for_mean(_v)}),
            steps=500, seeds=10))

register(Experiment(
    id="IV-7", title="Vision 1: thin market, high price variance (Figs IV-7, IV-8, p.117)",
    rules="({G1}, {M, T})", config=Config(**{**NEO, "vision": (1, 1)}), steps=1000, seeds=5))
register(Experiment(
    id="IV-9", title="Vision 1-15: thick market, low price variance (Fig IV-9, p.119)",
    rules="({G1}, {M, T})", config=Config(**{**NEO, "vision": (1, 15)}), steps=1000, seeds=5))

# Fig IV-12: long-run price dispersion vs average lifetime; (60,100) and (960,1000) are Figs IV-10, IV-11.
for _a, _b in ((60, 100), (280, 320), (530, 570), (960, 1000)):
    register(Experiment(
        id=f"IV-12/a{(_a + _b) // 2}", title=f"Price dispersion with lifetimes {_a}-{_b} (Figs IV-10 to IV-12)",
        rules=f"({{G1}}, {{M, R[{_a},{_b}], T}})",
        config=Config(**NEO, max_age=(_a, _b), replacement=True), steps=1000, seeds=5))

for _trade in (True, False):
    for _v in (1.5, 3.5, 5.5, 10, 14.5):
        register(Experiment(
            id=f"IV-13/{'trade' if _trade else 'notrade'}/v{_v:g}",
            title=f"Gini {'with' if _trade else 'without'} trade, mean vision {_v} (Fig IV-13, p.123)",
            rules="({G1}, {M, R[60,100], T})" if _trade else "({G1}, {M, R[60,100]})",
            config=Config(**{**NEO, "trade": _trade, "initial_population": 400, "vision": _vision_for_mean(_v)},
                          max_age=(60, 100), replacement=True),
            steps=500, seeds=10))

register(Experiment(
    id="IV-14", title="Trade with sexual reproduction (Fig IV-14, p.124)",
    rules="({G1}, {M, S, T})", config=Config(**{**NEO, **CH4_SEX}), steps=1000, seeds=5))
register(Experiment(
    id="IV-15", title="Culturally varying preferences (Figs IV-15, IV-16, p.125)",
    rules="({G1}, {M, K, T})",
    config=Config(**NEO, tag_length=TAGS, culture=True, cultural_preferences=True), steps=1000, seeds=5))
register(Experiment(
    id="IV-17", title="Cultural preferences with sexual reproduction (Fig IV-17, p.127)",
    rules="({G1}, {M, S, K, T})",
    config=Config(**{**NEO, **CH4_SEX}, tag_length=TAGS, culture=True, cultural_preferences=True),
    steps=1000, seeds=5))
register(Experiment(
    id="IV-A3", title="Pollution and prices (Animation IV-3, pp.127-129)",
    rules="({G1, D1}, {M, T, P})",
    # Sugar is dirty from t=100; at t=150 pollution stops and diffusion starts (p.128).
    config=Config(**NEO, pollution=(1.0, 1.0), pollution_start=100, pollution_stop=150,
                  diffusion_period=1, diffusion_start=150),
    steps=300, seeds=10))
register(Experiment(
    id="IV-18", title="Evolution of foresight (Fig IV-18, p.130)",
    rules="({G1}, {M, S})", config=Config(**{**NEO, **CH4_SEX, "trade": False}, foresight=(0, 10)),
    steps=1000, seeds=5))
register(Experiment(
    id="IV-A5", title="Credit networks on the sugar-only landscape (Animation IV-5, p.133)",
    rules="({G1}, {M, S, L10,10})", config=Config(**CH3_SEX, credit=(10, 10.0)), steps=500, seeds=5))
