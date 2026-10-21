"""Cultural tags, transmission K, group membership, and networks of friends (pp.72-80)."""

from collections.abc import Sequence


def tribe(tags: Sequence[int]) -> str:
    """Group membership (p.73): Blue when 0s outnumber 1s, Red otherwise."""
    return "blue" if 2 * sum(tags) < len(tags) else "red"


def random_tags(rng, length: int, tribe_name: str | None = None) -> list[int]:
    """A uniformly random tag string; with a tribe, resampled until its majority matches (our call)."""
    while True:
        tags = [int(v) for v in rng.integers(0, 2, size=length)]
        if tribe_name is None or tribe(tags) == tribe_name:
            return tags


def cross_tags(rng, a: Sequence[int], b: Sequence[int]) -> list[int]:
    """Vertical transmission (p.78, Table III-2): agreeing positions copy, others take a fair coin."""
    return [x if x == y else int(rng.integers(0, 2)) for x, y in zip(a, b)]


def hamming(a: Sequence[int], b: Sequence[int]) -> int:
    return sum(x != y for x, y in zip(a, b))


def closeness(a: Sequence[int], b: Sequence[int]) -> float:
    """Fraction of matching tags: 1 - Hamming distance / length."""
    return 1.0 - hamming(a, b) / len(a)


def transmit(model, agent) -> None:
    """Cultural transmission (p.73, App. B): for each neighbor, in random order, a random tag
    position is chosen; if the neighbor disagrees there, the neighbor's tag is flipped to the agent's.
    """
    neighbors = model.neighbors_of(agent)
    for i in model.rng.permutation(len(neighbors)):
        other = neighbors[int(i)]
        if other.tags is None:
            continue
        pos = int(model.rng.integers(len(agent.tags)))
        other.tags[pos] = agent.tags[pos]


def update_friends(agent, neighbors: Sequence, max_friends: int = 5) -> None:
    """Networks of friends (pp.79-80): remember the culturally nearest agents met as neighbors.

    Distances are taken at the encounter and never re-evaluated; dead friends are dropped (our call).
    A newcomer displaces the stored-farthest friend only when strictly closer.
    """
    agent.friends = [(f, d) for f, d in agent.friends if f.alive]
    for other in neighbors:
        if other is agent or other.tags is None or not other.alive:
            continue
        if any(f is other for f, _ in agent.friends):
            continue
        d = hamming(agent.tags, other.tags)
        if len(agent.friends) < max_friends:
            agent.friends.append((other, d))
            continue
        worst = max(range(len(agent.friends)), key=lambda i: agent.friends[i][1])
        if d < agent.friends[worst][1]:
            agent.friends[worst] = (other, d)
