"""Immune systems and disease processes E (Chapter V, pp.141-147; App. B p.185)."""

from collections.abc import Sequence


def nearest_substring(immune: Sequence[int], disease: Sequence[int]) -> tuple[int, int]:
    """(start, Hamming distance) of the window of the immune system closest to the disease;
    ties go to the leftmost window (p.142 fn 11)."""
    n = len(disease)
    best = (0, n + 1)
    for start in range(len(immune) - n + 1):
        d = sum(a != b for a, b in zip(immune[start : start + n], disease))
        if d < best[1]:
            best = (start, d)
            if d == 0:
                break
    return best


def is_immune(immune: Sequence[int], disease: Sequence[int]) -> bool:
    """Immune iff the disease is a substring of the immune system (p.142)."""
    return nearest_substring(immune, disease)[1] == 0


def immune_step(immune: list[int], disease: Sequence[int]) -> bool:
    """One period of learning (p.144): flip the first bit at which the nearest window differs from
    the disease. Returns whether the disease now matches."""
    start, distance = nearest_substring(immune, disease)
    if distance == 0:
        return True
    for i, bit in enumerate(disease):
        if immune[start + i] != bit:
            immune[start + i] = bit
            break
    return distance == 1


def infect(agent, disease: tuple[int, ...]) -> bool:
    """Contract a disease unless immune to it or already carrying it (p.145)."""
    if disease in agent.diseases or is_immune(agent.immune, disease):
        return False
    agent.diseases.append(disease)
    return True


def immune_response(agent) -> None:
    """Agent immune response rule (p.144), once per period for each carried disease, in order of
    infection; a disease is cleared the moment the immune system matches it, so a one-bit gap costs
    one period of illness (p.143)."""
    agent.diseases = [d for d in agent.diseases if not immune_step(agent.immune, d)]


def transmit(model, agent) -> None:
    """Agent disease transmission rule (p.145): for each neighbor, a disease that currently afflicts
    the agent is selected at random and given to the neighbor. New infections are logged as
    (source, target) for the transmission network (p.150)."""
    if not agent.diseases:
        return
    neighbors = model.neighbors_of(agent)
    for i in model.rng.permutation(len(neighbors)):
        other = neighbors[int(i)]
        disease = agent.diseases[int(model.rng.integers(len(agent.diseases)))]
        if other.immune is not None and infect(other, disease):
            model.infection_log.append((agent, other))
