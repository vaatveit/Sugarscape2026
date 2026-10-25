"""Agent sex rule S (pp.55-57, App. B p.183)."""

import math

from sugarscape.rules.culture import cross_tags
from sugarscape.rules.movement import look_distances

VON_NEUMANN = ((1, 0), (-1, 0), (0, 1), (0, -1))
GIFT_CAP = 5.0  # Ascape's most a parent gives a child (child_gift="capped")


def is_fertile(agent, threshold: float = 1.0) -> bool:
    """Of childbearing age and holding at least the sugar it was endowed with at birth (p.55).

    The wealth test is sugar only, as p.55 states, also on the sugar-and-spice landscape (user
    decision, 2026-10-21); parents still give half their initial spice to each child.
    `threshold` scales the requirement for the calibrated variant (Config.fertility_threshold).
    """
    return (
        agent.alive
        and agent.sex is not None
        and agent.fertility_start <= agent.age < agent.fertility_end
        and agent.sugar >= threshold * agent.initial_sugar
    )


def _rounded(gifts: list[float], down: bool) -> list[float]:
    return [float(math.floor(g)) for g in gifts] if down else gifts


def _empty_sites(model, agent) -> list[tuple[int, int]]:
    sites = (model.landscape.wrap(agent.x + dx, agent.y + dy) for dx, dy in VON_NEUMANN)
    return [s for s in sites if model.agent_at(*s) is None]


def in_sight(model, agent) -> list:
    """Agents within the agent's vision along the four lattice directions (rule M's lookout), nearest first:
    the partners of mate_contact="vision" (README candidate C1)."""
    lines = [(dx, dy, look_distances(model, agent.vision)) for dx, dy in VON_NEUMANN]
    found = []
    for k in range(len(lines[0][2])):  # stretch by stretch, so nearest first
        for dx, dy, dists in lines:
            other = model.agent_at(agent.x + dx * dists[k], agent.y + dy * dists[k])
            if other is not None:
                found.append(other)
    return found


def mate(model, agent) -> list:
    """Rule S: for each neighbor, in random order: if of the opposite sex, both fertile, and an
    empty site exists next to either parent, a child is born there (p.56).

    Each parent gives half of its own initial endowment (p.55). The child takes vision, metabolism,
    and maximum age each from a random parent (Table III-1) and crossed tags (p.78); its sex is a
    coin flip and its childbearing ages are drawn for its sex (our call). Placement among the empty
    sites is uniformly random (our call).

    Labelled departures (Config, off by default): mate_contact="vision" takes partners in sight, not only
    neighbors; child_gift="capped" has each parent give min(5, its current sugar and spice); child_threshold=
    "redraw" gives the child a fertility threshold drawn from the founders' endowment range; gift_rounding="down"
    rounds each parent's gift down to a whole unit (SugarscapeCW's int(endowment / 2); VAR-intgift).
    """
    rng = model.rng
    cfg = model.config
    threshold, share = cfg.fertility_threshold, cfg.child_share
    capped, redraw = cfg.child_gift == "capped", cfg.child_threshold == "redraw"
    rounded = cfg.gift_rounding == "down"
    children = []
    neighbors = in_sight(model, agent) if cfg.mate_contact == "vision" else model.neighbors_of(agent)
    for i in rng.permutation(len(neighbors)):
        other = neighbors[int(i)]
        if other.sex is None or other.sex == agent.sex or not (is_fertile(agent, threshold) and is_fertile(other, threshold)):
            continue
        sites = list(dict.fromkeys(_empty_sites(model, agent) + _empty_sites(model, other)))
        if not sites:
            continue
        x, y = sites[int(rng.integers(len(sites)))]
        parents = (agent, other)
        vision = parents[int(rng.integers(2))].vision
        metabolism = parents[int(rng.integers(2))].metabolism
        max_age = parents[int(rng.integers(2))].max_age
        gifts = _rounded([min(GIFT_CAP, max(p.sugar, 0.0)) if capped else p.initial_sugar * share for p in parents],
                         rounded)
        agent.sugar -= gifts[0]
        other.sugar -= gifts[1]
        child = model.new_agent(x, y, vision, metabolism, sum(gifts), max_age)
        if redraw:
            child.initial_sugar = float(rng.integers(cfg.endowment[0], cfg.endowment[1], endpoint=True))
        model._assign_sex(child, "F" if rng.integers(2) == 0 else "M")
        if agent.tags is not None and other.tags is not None:
            child.tags = cross_tags(rng, agent.tags, other.tags)
        if cfg.spice:  # Chapter IV: draws come last so earlier streams are unchanged
            spice_gifts = _rounded([min(GIFT_CAP, max(p.spice, 0.0)) if capped else p.initial_spice * share
                                    for p in parents], rounded)
            agent.spice -= spice_gifts[0]
            other.spice -= spice_gifts[1]
            child.spice = child.initial_spice = sum(spice_gifts)
            if redraw:
                lo, hi = cfg.spice_endowment or cfg.endowment
                child.initial_spice = float(rng.integers(lo, hi, endpoint=True))
            child.spice_metabolism = parents[int(rng.integers(2))].spice_metabolism
            child.foresight = parents[int(rng.integers(2))].foresight
        if cfg.disease_list:  # Chapter V: untrained genotypes are crossed (p.146)
            child.immune_genotype = cross_tags(rng, agent.immune_genotype, other.immune_genotype)
            child.immune = list(child.immune_genotype)
            child.disease_fee = model.config.disease_fee
        agent.children.append(child)
        other.children.append(child)
        children.append(child)
    return children
