"""Run configuration: one frozen dataclass naming every rule toggle and parameter.

Book page references are to Epstein & Axtell (1996). Fields marked "our call" fill
gaps the book leaves open; see docs/book-notes.md.
"""

from dataclasses import dataclass

PLACEMENTS = ("random", "block")


@dataclass(frozen=True)
class Config:
    # World (p.21: 50x50 torus).
    width: int = 50
    height: int = 50
    sugar_map: str = "sugar-map.txt"

    # Initial population (p.23: 400 random agents).
    initial_population: int = 400
    placement: str = "random"  # "random" | "block"
    block: tuple[int, int, int, int] = (0, 0, 20, 20)  # x0, y0, w, h; II-6 block is our call

    # Genetics and endowment, each an inclusive uniform integer range.
    vision: tuple[int, int] = (1, 6)  # p.24
    metabolism: tuple[int, int] = (1, 4)  # p.24
    endowment: tuple[int, int] = (5, 25)  # p.33; runs II-1/II-2 don't state it (our call)
    max_age: tuple[int, int] | None = None  # None = immortal unless starving (p.25)
    replacement: bool = False  # R[a,b] (p.32); requires max_age

    # Environment.
    growback_rate: float = 1.0  # alpha in G_alpha (p.23); math.inf = G_inf (p.26)
    seasons: tuple[int, int] | None = None  # (beta, gamma) of S_alpha,beta,gamma (p.44)
    pollution: tuple[float, float] | None = None  # (alpha, beta) of P_alpha,beta (p.47)
    pollution_start: int = 0
    diffusion_period: int | None = None  # alpha of D_alpha (p.48)
    diffusion_start: int = 0

    seed: int = 0

    def __post_init__(self) -> None:
        for name in ("vision", "metabolism", "endowment", "max_age"):
            rng = getattr(self, name)
            if rng is not None and rng[0] > rng[1]:
                raise ValueError(f"{name} range {rng} has low > high")
        # Agents see only along the four lattice directions; a vision of half the grid or
        # more would let opposite scans reach the same sites (Kehoe: MAXVISION << M).
        if self.vision[1] * 2 >= min(self.width, self.height):
            raise ValueError(
                f"max vision {self.vision[1]} must be less than half the grid "
                f"({self.width}x{self.height})"
            )
        if self.replacement and self.max_age is None:
            raise ValueError("replacement R[a,b] needs a max_age range [a, b]")
        if self.placement not in PLACEMENTS:
            raise ValueError(f"placement must be one of {PLACEMENTS}, not {self.placement!r}")
