"""The agent welfare function and marginal rate of substitution (Chapter IV, pp.97-104, 124)."""

import math


def preference_fraction(agent, cultural: bool) -> float:
    """f in eq. 5: the share of the agent's tags that are 0 when preferences are cultural (p.124);
    0.5 otherwise, which reduces eq. 5 to eq. 1."""
    if not cultural or agent.tags is None:
        return 0.5
    return (len(agent.tags) - sum(agent.tags)) / len(agent.tags)


def welfare(agent, w1: float, w2: float, cultural: bool = False) -> float:
    """W(w1, w2) = w1^(m1 f / mu) * w2^(m2 (1 - f) / mu), mu = m1 f + m2 (1 - f) (eqs. 1 and 5).

    With f = 1/2 this is eq. 1, w1^(m1/mT) w2^(m2/mT). Holdings below 0 count as 0 (eq. 6's
    convention); a zero exponent makes that factor 1.
    """
    f = preference_fraction(agent, cultural)
    a1, a2 = agent.metabolism * f, agent.spice_metabolism * (1 - f)
    mu = a1 + a2
    w1, w2 = max(w1, 0.0), max(w2, 0.0)
    left = w1 ** (a1 / mu) if a1 else 1.0
    right = w2 ** (a2 / mu) if a2 else 1.0
    return left * right


def mrs(agent, cultural: bool = False) -> float:
    """Spice the agent would give for one sugar: (w2 / (m2 (1-f))) / (w1 / (m1 f)) (eq. 3; eq. 5 form).

    With f = 1/2 this is (w2/m2) / (w1/m1) = tau2 / tau1 (p.102). Returns 0.0 or math.inf when a
    holding or a preference weight is zero.
    """
    f = preference_fraction(agent, cultural)
    a1, a2 = agent.metabolism * f, agent.spice_metabolism * (1 - f)
    w1, w2 = max(agent.sugar, 0.0), max(agent.spice, 0.0)
    numerator = math.inf if a2 == 0 else w2 / a2
    denominator = math.inf if a1 == 0 else w1 / a1
    if denominator == 0:
        return math.inf if numerator > 0 else math.nan
    if math.isinf(denominator):
        return 0.0 if math.isfinite(numerator) else math.nan
    return numerator / denominator
