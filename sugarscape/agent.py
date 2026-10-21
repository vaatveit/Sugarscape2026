"""The single agent class (App. A, p.180: one class carries every rule's state)."""

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
