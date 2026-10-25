"""Model.random_empty_site: which site it draws, and that it stays quick on an xl-sized lattice (rule R, p.32)."""

import copy
import time

import numpy as np

from conftest import put_agent, tiny_model


def scanned_draw(model, rng):
    """The draw as first written: scan x then y for empty sites, then pick one with rng.integers."""
    w, h = model.config.width, model.config.height
    empty = [(x, y) for x in range(w) for y in range(h) if model.agent_at(x, y) is None]
    return empty[int(rng.integers(len(empty)))]


def test_draws_the_same_site_as_a_scan_of_the_lattice():
    # Non-square, so swapping x and y would show. Pins the random stream of every run with replacement.
    m = tiny_model(np.ones((7, 5), dtype=int))
    agents = [put_agent(m, x, y) for x, y in [(0, 0), (6, 4), (3, 2), (1, 4), (5, 0)]]
    m.move_agent(agents[2], 4, 1)
    m.kill(agents[1])
    for _ in range(25):
        rng = copy.deepcopy(m.rng)
        site = m.random_empty_site()
        assert site == scanned_draw(m, rng)
        assert m.rng.bit_generator.state == rng.bit_generator.state
        put_agent(m, *site)  # fill it, so the next draw sees the change
    assert all(isinstance(v, int) for v in site)


def test_is_quick_on_a_500_by_500_lattice():
    # xl II-4-gini replaces about 900 agents a period; scanning 250,000 sites for each took 16 s a period.
    m = tiny_model(np.ones((500, 500), dtype=int))
    start = time.perf_counter()
    for _ in range(300):
        put_agent(m, *m.random_empty_site())
    assert time.perf_counter() - start < 1.0
