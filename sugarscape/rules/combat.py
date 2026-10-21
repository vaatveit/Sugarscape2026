"""Agent combat rule C_alpha (pp.82-83, App. B p.183-184). Replaces movement M when active."""

VON_NEUMANN = ((1, 0), (-1, 0), (0, 1), (0, -1))


def combat_candidates(model, agent) -> list[tuple[int, int, int, float, object]]:
    """(x, y, distance, reward, victim) for every site the agent may take, in scan order.

    The current site comes first at distance 0, then each direction in random order out to vision
    (as in M). Sites held by the agent's own tribe or by anyone wealthier are thrown out; sight
    continues past them. Reward = site sugar + min(alpha, occupant's wealth) if occupied.
    """
    ls = model.landscape
    alpha = model.config.combat_alpha
    sites = [(agent.x, agent.y, 0, float(ls.sugar[agent.x, agent.y]), None)]
    for d in model.rng.permutation(4):
        dx, dy = VON_NEUMANN[d]
        for dist in range(1, agent.vision + 1):
            x, y = ls.wrap(agent.x + dx * dist, agent.y + dy * dist)
            occupant = model.agent_at(x, y)
            if occupant is None:
                sites.append((x, y, dist, float(ls.sugar[x, y]), None))
            elif occupant.tribe != agent.tribe and occupant.sugar <= agent.sugar:
                reward = float(ls.sugar[x, y]) + min(alpha, occupant.sugar)
                sites.append((x, y, dist, reward, occupant))
    return sites


def vulnerable(model, agent, x: int, y: int, reward: float, victim) -> bool:
    """A site is vulnerable to retaliation if an agent of another tribe within the attacker's vision
    of that site would be bigger than the attacker after taking it (p.82; Kehoe on the viewpoint).
    """
    after = agent.sugar + reward
    for dx, dy in VON_NEUMANN:
        for dist in range(1, agent.vision + 1):
            other = model.agent_at(x + dx * dist, y + dy * dist)
            if (
                other is not None
                and other is not agent
                and other is not victim
                and other.tribe != agent.tribe
                and other.sugar > after
            ):
                return True
    return False


def combat_move(model, agent) -> None:
    """Rule C_alpha: take the nearest safe site of maximum reward; a defeated occupant is killed.

    With no safe site the agent stays and harvests where it is (Kehoe; harvesting is our call).
    """
    candidates = combat_candidates(model, agent)
    safe = [c for c in candidates if not vulnerable(model, agent, c[0], c[1], c[3], c[4])]
    if safe:
        best = safe[0]
        for c in safe[1:]:  # strict comparisons keep the first encountered on ties
            if c[3] > best[3] or (c[3] == best[3] and c[2] < best[2]):
                best = c
    else:
        best = candidates[0]
    x, y, _, _, victim = best
    if victim is not None:
        take = min(model.config.combat_alpha, victim.sugar)
        victim.sugar -= take
        agent.sugar += take
        model.die(victim)
    agent.moved = (x, y) != (agent.x, agent.y)
    model.move_agent(agent, x, y)
    ls = model.landscape
    agent.sugar += ls.sugar[x, y]
    ls.sugar[x, y] = 0.0
