"""Run configuration: one frozen dataclass naming every rule toggle and parameter.

Book page references are to Epstein & Axtell (1996). Fields marked "our call" fill
gaps the book leaves open; see docs/book-notes.md.
"""

from dataclasses import dataclass, field

PLACEMENTS = ("random", "block")
WINTER_MODES = ("fractional", "pulse")
TRIBES = ("blue", "red")
FOUNDER_AGES = ("uniform", "zero")
MATE_CONTACTS = ("neighbors", "vision")
CHILD_GIFTS = ("endowment", "capped")
CHILD_THRESHOLDS = ("endowment", "redraw")


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
    # With finite lives, founders start at ages U[0, max age): Animation III-1's first frame (an age
    # spread, 417 agents), Fig III-1 starting near 417, VI-2's early births, Ascape's code.
    # "zero" starts every founder at birth. Newborns and replacements are always age 0.
    founder_ages: str = "uniform"  # "uniform" | "zero"
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
    # Reproduction (docs/replication/chapter-3.md). p.55's rule is a threshold of 1.0 (the whole birth
    # endowment). The default 0.83 is a fitted departure (fitted to Fig III-1's steady population alone),
    # adopted by user decision 2026-10-22; the book's rule runs as the VAR-book experiments.
    fertility_threshold: float = 0.83  # share of its birth endowment an agent must hold to be fertile
    child_share: float = 0.5  # share of its initial endowment each parent gives a child (p.55)
    # Labelled departures from rule S (README candidates C1 and C3; VAR-c1c3fit), off by default. Left out of
    # repr so saved results' fingerprints are unchanged; experiments.run.fingerprint adds them when set.
    mate_contact: str = field(default="neighbors", repr=False)  # "vision": partners in sight along the lattice
    child_gift: str = field(default="endowment", repr=False)  # "capped": each parent gives min(5, its sugar)
    child_threshold: str = field(default="endowment", repr=False)  # "redraw": from the founders' range

    # Chapter IV. New draws are gated by these and come after earlier draws.
    spice: bool = False  # second commodity (p.96); spice map = sugar map mirrored east-west
    spice_metabolism: tuple[int, int] = (1, 5)  # p.108
    spice_endowment: tuple[int, int] | None = None  # None = same range as endowment
    foresight: tuple[int, int] | None = None  # phi range (p.129); None = myopic
    cultural_preferences: bool = False  # eq. 5 (p.124); needs tags
    trade: bool = False  # rule T (p.105); needs spice
    credit: tuple[int, float] | None = None  # (duration d, rate r percent) of L_dr (p.132); sugar loans
    pollution_stop: int | None = None  # pollution generation off from this t (p.128)

    # Chapter V. New draws are gated by disease_list > 0 and come after earlier draws.
    disease_list: int = 0  # master disease list size (p.147); 0 = no disease
    diseases_per_agent: int = 0  # distinct diseases offered to each initial agent (p.147)
    disease_length: tuple[int, int] = (1, 10)  # p.147
    immune_length: int = 50  # p.147
    disease_fee: float = 1.0  # extra sugar metabolism per active disease ("say, one", p.143)

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
        for name, allowed in (("mate_contact", MATE_CONTACTS), ("child_gift", CHILD_GIFTS),
                              ("child_threshold", CHILD_THRESHOLDS)):
            if getattr(self, name) not in allowed:
                raise ValueError(f"{name} must be one of {allowed}, not {getattr(self, name)!r}")
        if self.founder_ages not in FOUNDER_AGES:
            raise ValueError(f"founder_ages must be one of {FOUNDER_AGES}, not {self.founder_ages!r}")
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
            if not self.sex:
                raise ValueError("credit L_dr lends for childbearing; it needs sex=True")
            if self.combat_alpha is not None:
                raise ValueError("credit needs each agent's income, which combat movement doesn't record")
            if d < 1 or r < 0:
                raise ValueError(f"credit duration must be >= 1 and rate >= 0, not {self.credit}")
        if self.disease_list < 0 or self.diseases_per_agent < 0:
            raise ValueError("disease_list and diseases_per_agent must be >= 0")
        if self.diseases_per_agent > self.disease_list:
            raise ValueError(f"cannot offer {self.diseases_per_agent} distinct diseases from a list of {self.disease_list}")
        if self.disease_length[0] < 1 or self.disease_length[0] > self.disease_length[1]:
            raise ValueError(f"disease_length {self.disease_length} must be a range starting at >= 1")
        if self.disease_length[1] >= self.immune_length:
            raise ValueError("diseases must be shorter than immune systems (p.141)")
        if self.disease_fee < 0:
            raise ValueError(f"disease_fee must be >= 0, not {self.disease_fee}")
        if self.pollution_stop is not None and self.pollution_stop <= self.pollution_start:
            raise ValueError("pollution_stop must come after pollution_start")
        if self.fertility_threshold <= 0:
            raise ValueError(f"fertility_threshold must be > 0, not {self.fertility_threshold}")
        if not 0 < self.child_share <= 1:
            raise ValueError(f"child_share must lie in (0, 1], not {self.child_share}")
        if self.replacement_same_tribe and not self.replacement:
            raise ValueError("replacement_same_tribe needs replacement=True")
        if self.placement == "block" and not (1 <= w <= self.width and 1 <= h <= self.height):
            raise ValueError(f"block {self.block} must have 1 <= w <= {self.width} and 1 <= h <= {self.height}")
