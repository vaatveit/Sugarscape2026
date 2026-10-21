"""Agent movement rule M, harvesting, metabolism, and pollution formation P.

M (p.25, App. B p.182): look out as far as vision permits in the four lattice directions;
considering only unoccupied positions, find the nearest position of maximum welfare; move
there and collect all the resources. The direction search order is random (fn 8); ties at
equal distance go to the first site encountered (fn 9).
"""

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
    return model.config.pollution is not None and model.t >= model.config.pollution_start


def move(model, agent) -> None:
    """Rule M: go to the nearest best site in view and harvest it (p.25)."""
    best = None  # (score, distance, x, y); strict comparisons keep the first encountered
    for x, y, dist in candidate_sites(model, agent):
        score = site_score(model, x, y)
        if best is None or score > best[0] or (score == best[0] and dist < best[1]):
            best = (score, dist, x, y)
    _, _, x, y = best
    agent.moved = (x, y) != (agent.x, agent.y)
    model.move_agent(agent, x, y)

    ls = model.landscape
    harvest = ls.sugar[x, y]
    agent.sugar += harvest
    ls.sugar[x, y] = 0.0
    if pollution_active(model):
        alpha, _ = model.config.pollution
        ls.pollution[x, y] += alpha * harvest  # production pollution (p.47)


def metabolize(model, agent) -> None:
    """Burn sugar at the metabolic rate; starve at zero or below (p.25)."""
    agent.sugar -= agent.metabolism
    if pollution_active(model):
        _, beta = model.config.pollution
        model.landscape.pollution[agent.x, agent.y] += beta * agent.metabolism  # consumption (p.47)
    if agent.sugar <= 0:
        model.kill(agent)
