"""Agent sex rule S (pp.55-57, App. B p.183)."""

from sugarscape.rules.culture import cross_tags

VON_NEUMANN = ((1, 0), (-1, 0), (0, 1), (0, -1))


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


def _empty_sites(model, agent) -> list[tuple[int, int]]:
    sites = (model.landscape.wrap(agent.x + dx, agent.y + dy) for dx, dy in VON_NEUMANN)
    return [s for s in sites if model.agent_at(*s) is None]


def mate(model, agent) -> list:
    """Rule S: for each neighbor, in random order: if of the opposite sex, both fertile, and an
    empty site exists next to either parent, a child is born there (p.56).

    Each parent gives half of its own initial endowment (p.55). The child takes vision, metabolism,
    and maximum age each from a random parent (Table III-1) and crossed tags (p.78); its sex is a
    coin flip and its childbearing ages are drawn for its sex (our call). Placement among the empty
    sites is uniformly random (our call).
    """
    rng = model.rng
    threshold, share = model.config.fertility_threshold, model.config.child_share
    children = []
    neighbors = model.neighbors_of(agent)
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
        endowment = agent.initial_sugar * share + other.initial_sugar * share
        agent.sugar -= agent.initial_sugar * share
        other.sugar -= other.initial_sugar * share
        child = model.new_agent(x, y, vision, metabolism, endowment, max_age)
        model._assign_sex(child, "F" if rng.integers(2) == 0 else "M")
        if agent.tags is not None and other.tags is not None:
            child.tags = cross_tags(rng, agent.tags, other.tags)
        if model.config.spice:  # Chapter IV: draws come last so earlier streams are unchanged
            agent.spice -= agent.initial_spice * share
            other.spice -= other.initial_spice * share
            child.spice = child.initial_spice = agent.initial_spice * share + other.initial_spice * share
            child.spice_metabolism = parents[int(rng.integers(2))].spice_metabolism
            child.foresight = parents[int(rng.integers(2))].foresight
        if model.config.disease_list:  # Chapter V: untrained genotypes are crossed (p.146)
            child.immune_genotype = cross_tags(rng, agent.immune_genotype, other.immune_genotype)
            child.immune = list(child.immune_genotype)
            child.disease_fee = model.config.disease_fee
        agent.children.append(child)
        other.children.append(child)
        children.append(child)
    return children
