"""Run configuration: one frozen dataclass naming every rule toggle and parameter.

Book page references are to Epstein & Axtell (1996). Fields marked "our call" fill
gaps the book leaves open; see docs/book-notes.md.
"""

from dataclasses import dataclass

PLACEMENTS = ("random", "block")
WINTER_MODES = ("fractional", "pulse")
TRIBES = ("blue", "red")


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
    # Winter grows "alpha units per beta time intervals" (p.44). "fractional" adds alpha/beta
    # every period (design spec); "pulse" adds alpha on periods with t % beta == 0.
    winter_growback: str = "fractional"
    pollution: tuple[float, float] | None = None  # (alpha, beta) of P_alpha,beta (p.47)
    pollution_start: int = 0
    diffusion_period: int | None = None  # alpha of D_alpha (p.48)
    diffusion_start: int = 0

    # Chapter III. Every new random draw is gated by one of these, so Chapter II runs keep
    # their exact random streams.
    sex: bool = False  # rule S (p.56)
    fertility_start: tuple[int, int] = (12, 15)  # p.57, both sexes
    female_fertility_end: tuple[int, int] = (40, 50)  # p.57
    male_fertility_end: tuple[int, int] = (50, 60)  # p.57
    inheritance: bool = False  # rule I (p.67)
    tag_length: int = 0  # 0 = no cultural tags; K needs an odd length (p.72-73; 11 standard)
    culture: bool = False  # rule K: tag flipping + group membership (p.73)
    combat_alpha: float | None = None  # None = movement M; math.inf = C_inf (p.83)
    # (tribe "blue"|"red", x0, y0, w, h, n); non-empty replaces placement/initial_population
    initial_blocks: tuple[tuple[str, int, int, int, int, int], ...] = ()
    replacement_same_tribe: bool = False  # R with newcomers of the dead agent's tribe (p.86)

    # Chapter IV. New draws are gated by these and come after earlier draws.
    spice: bool = False  # second commodity (p.96); spice map = sugar map mirrored east-west
    spice_metabolism: tuple[int, int] = (1, 5)  # p.108
    spice_endowment: tuple[int, int] | None = None  # None = same range as endowment
    foresight: tuple[int, int] | None = None  # phi range (p.129); None = myopic
    cultural_preferences: bool = False  # eq. 5 (p.124); needs tags
    trade: bool = False  # rule T (p.105); needs spice
    credit: tuple[int, float] | None = None  # (duration d, rate r percent) of L_dr (p.132); sugar only
    pollution_stop: int | None = None  # pollution generation off from this t (p.128)

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
        if self.winter_growback not in WINTER_MODES:
            raise ValueError(f"winter_growback must be one of {WINTER_MODES}, not {self.winter_growback!r}")
        if self.initial_population < 0:
            raise ValueError(f"initial_population must be >= 0, not {self.initial_population}")
        if self.growback_rate < 0:
            raise ValueError(f"growback_rate must be >= 0, not {self.growback_rate}")
        if self.seasons is not None and min(self.seasons) < 1:
            raise ValueError(f"seasons (beta, gamma) must both be >= 1, not {self.seasons}")
        if self.diffusion_period is not None and self.diffusion_period < 1:
            raise ValueError(f"diffusion_period must be None or >= 1, not {self.diffusion_period}")
        if self.pollution is not None and min(self.pollution) < 0:
            raise ValueError(f"pollution coefficients must be >= 0, not {self.pollution}")
        _, _, w, h = self.block
        for name in ("fertility_start", "female_fertility_end", "male_fertility_end"):
            rng = getattr(self, name)
            if rng[0] > rng[1]:
                raise ValueError(f"{name} range {rng} has low > high")
        if self.tag_length < 0 or (self.tag_length and self.tag_length % 2 == 0):
            raise ValueError(f"tag_length must be 0 or odd (so groups have a majority), not {self.tag_length}")
        if self.tag_length == 0 and (self.culture or self.combat_alpha is not None or self.initial_blocks):
            raise ValueError("culture, combat, and tribal blocks need cultural tags (tag_length > 0)")
        if self.combat_alpha is not None and self.combat_alpha < 0:
            raise ValueError(f"combat_alpha must be >= 0, not {self.combat_alpha}")
        for tribe, x0, y0, bw, bh, n in self.initial_blocks:
            if tribe not in TRIBES:
                raise ValueError(f"block tribe must be one of {TRIBES}, not {tribe!r}")
            if not (0 <= x0 and 0 <= y0 and x0 + bw <= self.width and y0 + bh <= self.height and bw >= 1 and bh >= 1):
                raise ValueError(f"block {(tribe, x0, y0, bw, bh, n)} must lie inside the {self.width}x{self.height} grid")
            if not 0 <= n <= bw * bh:
                raise ValueError(f"block {(tribe, x0, y0, bw, bh, n)} cannot hold {n} agents")
        for name in ("spice_metabolism", "spice_endowment", "foresight"):
            rng = getattr(self, name)
            if rng is not None and rng[0] > rng[1]:
                raise ValueError(f"{name} range {rng} has low > high")
        if not self.spice and (self.trade or self.cultural_preferences or self.foresight is not None):
            raise ValueError("trade, cultural preferences, and foresight need the second commodity (spice=True)")
        if self.cultural_preferences and self.tag_length == 0:
            raise ValueError("cultural preferences need cultural tags (tag_length > 0)")
        if self.spice and self.combat_alpha is not None:
            raise ValueError("combat is defined for sugar only (p.83); not with spice")
        if self.credit is not None:
            d, r = self.credit
            if self.spice:
                raise ValueError("credit is implemented for the one-commodity landscape (p.133)")
            if not self.sex:
                raise ValueError("credit L_dr lends for childbearing; it needs sex=True")
            if d < 1 or r < 0:
                raise ValueError(f"credit duration must be >= 1 and rate >= 0, not {self.credit}")
        if self.pollution_stop is not None and self.pollution_stop <= self.pollution_start:
            raise ValueError("pollution_stop must come after pollution_start")
        if self.replacement_same_tribe and not self.replacement:
            raise ValueError("replacement_same_tribe needs replacement=True")
        if self.placement == "block" and not (1 <= w <= self.width and 1 <= h <= self.height):
            raise ValueError(f"block {self.block} must have 1 <= w <= {self.width} and 1 <= h <= {self.height}")
