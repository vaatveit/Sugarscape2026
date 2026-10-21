"""The experiment registry: each entry pairs a book label with its rules and parameters."""

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
