"""The single agent class (App. A, p.180: one class carries every rule's state)."""

import math
from dataclasses import dataclass, field


@dataclass(eq=False)
class Agent:
    id: int
    x: int
    y: int
    vision: int  # genetic, fixed for life (p.24)
    metabolism: int  # genetic, fixed for life (p.24)
    sugar: float  # accumulated wealth (p.24)
    initial_sugar: float  # endowment at birth (p.55)
    max_age: float  # math.inf when lives are unbounded
    age: int = 0
    alive: bool = True
    moved: bool = False  # changed site this period
    neighbors: list["Agent"] = field(default_factory=list)  # post-move von Neumann neighbors (p.39)
    # Chapter III
    sex: str | None = None  # "F" | "M" when Config.sex
    fertility_start: float = math.inf  # childbearing ages (p.57); default: never fertile
    fertility_end: float = -math.inf
    children: list["Agent"] = field(default_factory=list)
    tags: list[int] | None = None  # cultural tag string (p.72)
    friends: list[tuple["Agent", int]] = field(default_factory=list)  # (friend, Hamming distance at encounter)
    # Chapter IV
    spice: float = 0.0
    initial_spice: float = 0.0
    spice_metabolism: int = 0
    foresight: int = 0  # phi (p.129)
    last_income: float = 0.0  # last period's sugar harvest minus metabolism (credit, p.132)
    # Chapter V
    immune_genotype: list[int] | None = None  # untrained template, passed to children (p.146)
    immune: list[int] | None = None  # trained phenotype (p.146)
    diseases: list[tuple[int, ...]] = field(default_factory=list)  # active infections
    disease_fee: float = 0.0  # extra sugar metabolism per active disease (p.143)
    disp_x: int = 0  # net displacement since birth, unwrapped across the torus edges
    disp_y: int = 0

    @property
    def sugar_burn(self) -> float:
        """Sugar metabolism including the fee for each active disease (p.143)."""
        return self.metabolism + self.disease_fee * len(self.diseases)

    @property
    def tribe(self) -> str | None:
        """Blue when 0s outnumber 1s, Red otherwise (p.73); None without tags."""
        if self.tags is None:
            return None
        return "blue" if 2 * sum(self.tags) < len(self.tags) else "red"
