"""Agent movement rule M, harvesting, metabolism, and pollution formation P.

M (p.25, App. B p.182): look out as far as vision permits in the four lattice directions;
considering only unoccupied positions, find the nearest position of maximum welfare; move
there and collect all the resources. The direction search order is random (fn 8); ties at
equal distance go to the first site encountered (fn 9).
"""

from sugarscape.rules.welfare import welfare

VON_NEUMANN = ((1, 0), (-1, 0), (0, 1), (0, -1))


def site_score(model, x: int, y: int) -> float:
    """Sugar-to-pollution ratio s/(1+p) (p.47 fn 37); equals plain sugar while p = 0."""
    ls = model.landscape
    return ls.sugar[x, y] / (1.0 + ls.pollution[x, y])


def candidate_sites(model, agent) -> list[tuple[int, int, int]]:
    """(x, y, distance) for every site the agent may move to, in scan order.

    The agent's own site comes first at distance 0 (a move to it means staying; Kehoe's
    reading, consistent with the book). Then each direction, in a random order, out to vision.
    """
    ls = model.landscape
    sites = [(agent.x, agent.y, 0)]
    for d in model.rng.permutation(4):
        dx, dy = VON_NEUMANN[d]
        for dist in range(1, agent.vision + 1):
            x, y = ls.wrap(agent.x + dx * dist, agent.y + dy * dist)
            if model.agent_at(x, y) is None:
                sites.append((x, y, dist))
    return sites


def pollution_active(model) -> bool:
    cfg = model.config
    if cfg.pollution is None or model.t < cfg.pollution_start:
        return False
    return cfg.pollution_stop is None or model.t < cfg.pollution_stop


def welfare_scorer(model, agent):
    """Two-commodity site score: W(w1 + sugar, w2 + spice) (App. B), evaluated as if phi periods
    ahead (eq. 6: holdings reduced by phi * metabolism). Pollution devalues the site's resources,
    x / (1 + pollution), as in the one-commodity rule (p.47 fn 37); dividing the agent's whole
    welfare instead (Kehoe) would let pollution swamp every choice."""
    ls = model.landscape
    cultural = model.config.cultural_preferences
    phi = agent.foresight
    base1 = agent.sugar - phi * agent.metabolism
    base2 = agent.spice - phi * agent.spice_metabolism

    def score(x: int, y: int) -> float:
        devalue = 1.0 + ls.pollution[x, y]
        return welfare(
            agent, max(base1, 0.0) + ls.sugar[x, y] / devalue, max(base2, 0.0) + ls.spice[x, y] / devalue, cultural
        )

    return score


def move(model, agent) -> None:
    """Rule M: go to the nearest best site in view and harvest it (p.25)."""
    score_at = welfare_scorer(model, agent) if model.config.spice else (lambda x, y: site_score(model, x, y))
    best = None  # (score, distance, x, y); strict comparisons keep the first encountered
    for x, y, dist in candidate_sites(model, agent):
        score = score_at(x, y)
        if best is None or score > best[0] or (score == best[0] and dist < best[1]):
            best = (score, dist, x, y)
    _, _, x, y = best
    agent.moved = (x, y) != (agent.x, agent.y)
    model.move_agent(agent, x, y)

    ls = model.landscape
    harvest = ls.sugar[x, y]
    agent.sugar += harvest
    ls.sugar[x, y] = 0.0
    agent.last_income = float(harvest)  # metabolize subtracts metabolism
    if model.config.spice:
        agent.spice += ls.spice[x, y]
        ls.spice[x, y] = 0.0
    if pollution_active(model):
        alpha, _ = model.config.pollution
        ls.pollution[x, y] += alpha * harvest  # production pollution (p.47)


def metabolize(model, agent) -> None:
    """Burn sugar (and spice) at the metabolic rates; die when either reaches zero (p.25, p.97).

    Pollution comes from sugar only: spice is a clean good (p.127).
    """
    agent.sugar -= agent.metabolism
    agent.last_income -= agent.metabolism
    if model.config.spice:
        agent.spice -= agent.spice_metabolism
    if pollution_active(model):
        _, beta = model.config.pollution
        model.landscape.pollution[agent.x, agent.y] += beta * agent.metabolism  # consumption (p.47)
    if agent.sugar <= 0 or (model.config.spice and agent.spice <= 0):
        model.die(agent)
