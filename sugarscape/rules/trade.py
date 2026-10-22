"""Agent trade rule T: bilateral exchange of sugar and spice (pp.101-107, App. B p.184)."""

import math
from dataclasses import dataclass

from sugarscape.rules.welfare import mrs, welfare


@dataclass(frozen=True)
class Exchange:
    price: float  # spice per sugar
    sugar: float  # sugar moved (to the higher-MRS agent)
    spice: float  # spice moved (to the lower-MRS agent)
    a: object
    b: object


def _valid(value: float) -> bool:
    return math.isfinite(value) and value > 0


def bargain(model, a, b) -> list[Exchange]:
    """Rule T between two neighbors (p.105).

    While their MRSs differ: the price is the geometric mean of the MRSs (eq. 4); the agent with
    the higher MRS buys sugar with spice (p > 1: p spice for 1 sugar; p < 1: 1 spice for 1/p sugar).
    The exchange happens only if both agents' welfare strictly rises and their MRSs don't cross
    (fn 17); otherwise bargaining ends. An MRS of 0, infinity, or undefined means no trade (our call).
    """
    cultural = model.config.cultural_preferences
    deals: list[Exchange] = []
    while True:
        ma, mb = mrs(a, cultural), mrs(b, cultural)
        if not (_valid(ma) and _valid(mb)) or ma == mb:
            return deals
        hi, lo = (a, b) if ma > mb else (b, a)
        price = math.sqrt(ma * mb)
        sugar, spice = (1.0, price) if price > 1 else ((1.0 / price, 1.0) if price < 1 else (1.0, 1.0))
        old = (hi.sugar, hi.spice, lo.sugar, lo.spice)
        before = (welfare(hi, hi.sugar, hi.spice, cultural), welfare(lo, lo.sugar, lo.spice, cultural))
        hi.sugar, hi.spice = hi.sugar + sugar, hi.spice - spice
        lo.sugar, lo.spice = lo.sugar - sugar, lo.spice + spice
        accepted = (
            min(hi.sugar, hi.spice, lo.sugar, lo.spice) > 0
            and welfare(hi, hi.sugar, hi.spice, cultural) > before[0]
            and welfare(lo, lo.sugar, lo.spice, cultural) > before[1]
            and mrs(hi, cultural) >= mrs(lo, cultural)  # no crossing over
        )
        if not accepted:
            hi.sugar, hi.spice, lo.sugar, lo.spice = old
            return deals
        if __debug__:
            assert math.isclose(hi.sugar + lo.sugar, old[0] + old[2]) and math.isclose(hi.spice + lo.spice, old[1] + old[3])
        deals.append(Exchange(price, sugar, spice, hi, lo))


def trade_with_neighbors(model, agent) -> None:
    """After moving, an agent trades through T exactly once with each neighbor, in random order (p.107)."""
    neighbors = model.neighbors_of(agent)
    for i in model.rng.permutation(len(neighbors)):
        model.trade_log.extend(bargain(model, agent, neighbors[int(i)]))
