import threading
from dataclasses import replace

import numpy as np
import pytest

from conftest import put_agent, tiny_model
from experiments.registry import EXPERIMENTS
from sugarscape.config import Config
from sugarscape.model import Model
from viewer.frames import capture
from viewer.run import KEEP, LEAD, NotKept, Run, RunBroken, catalog


def reference(exp_id, k, t):
    exp = EXPERIMENTS[exp_id]
    m = Model(replace(exp.config, seed=exp.config.seed + k))
    for _ in range(t):
        m.step()
    return m


@pytest.mark.parametrize("exp_id", ["II-4", "VI-1"])
@pytest.mark.parametrize("t", [0, 1, 7, 20])
def test_frame_matches_an_independent_model(exp_id, t):
    run, m = Run(exp_id, 1), reference(exp_id, 1, t)
    j = run.frame(t).to_json()
    assert j["t"] == t == m.t and j["population"] == len(m.agents)
    assert j["sugar"] == m.landscape.sugar.ravel().tolist()
    assert j["spice"] == (m.landscape.spice.ravel().tolist() if m.config.spice else None)
    a = j["agents"]
    assert a["id"] == [g.id for g in m.agents]
    assert list(zip(a["x"], a["y"])) == [(g.x, g.y) for g in m.agents]
    assert a["sugar"] == [g.sugar for g in m.agents] and a["spice"] == [g.spice for g in m.agents]
    assert a["tribe"] == [g.tribe for g in m.agents] and a["sex"] == [g.sex for g in m.agents]
    assert a["vision"] == [g.vision for g in m.agents] and a["metabolism"] == [g.metabolism for g in m.agents]
    assert a["age"] == [g.age for g in m.agents]


def test_each_run_has_its_own_id():
    a, b = Run("II-4", 0), Run("II-4", 0)
    assert a.id != b.id and a.info()["run"] == a.id and a.frame(0).to_json()["t"] == 0


@pytest.mark.parametrize("exp_id", ["III-1", "III-9", "IV-14", "VI-1"])
def test_every_frame_has_at_most_one_agent_per_cell(exp_id):
    # Hover shows the one agent in a cell; this pins the model invariant it relies on, including under combat
    # (III-9), sex and replacement.
    run = Run(exp_id, 0)
    for t in range(0, 41):
        a = run.frame(t).to_json()["agents"]
        cells = list(zip(a["x"], a["y"]))
        assert len(cells) == len(set(cells)), (exp_id, t)


def test_seed_index_offsets_the_registered_seed():
    assert Run("II-4", 3).seed == EXPERIMENTS["II-4"].config.seed + 3


def test_scrubbing_back_returns_the_frame_first_recorded():
    run = Run("VI-1", 0)
    first = run.frame(3).to_json()
    run.frame(30)
    assert run.frame(3).to_json() == first and run.latest == 30


def test_requests_beyond_the_lead_are_refused():
    run = Run("II-4", 0)
    with pytest.raises(ValueError):
        run.frame(LEAD + 1)
    with pytest.raises(ValueError):
        run.frame(-1)
    assert run.latest == 0


def test_a_model_error_stops_the_run_where_it_broke():
    # A step that raises may leave the model half-updated, so nothing past it is computed again (final review #3).
    run = Run("II-4", 0)
    run.frame(3)
    real = run.model.step

    def broken():
        raise RuntimeError("boom")

    run.model.step = broken
    with pytest.raises(RuntimeError, match="boom"):
        run.frame(4)
    run.model.step = real
    with pytest.raises(RunBroken, match="boom"):
        run.frame(4)
    assert run.latest == 3 and run.frame(3).t == 3 and run.frame(0).t == 0


def step_to(run, t):
    while run.latest < t:
        run.frame(min(t, run.latest + LEAD))


def test_only_the_last_KEEP_periods_are_kept():
    # Memory stays bounded on long runs (user decision 2026-10-24); the population series stays whole.
    run = Run("II-4", 0)
    step_to(run, KEEP + 30)
    assert run.earliest == run.latest - KEEP + 1 == 31 and len(run._frames) == KEEP
    m = reference("II-4", 0, run.earliest)
    j = run.frame(run.earliest).to_json()
    assert j["t"] == run.earliest and j["agents"]["id"] == [g.id for g in m.agents]
    assert j["sugar"] == m.landscape.sugar.ravel().tolist()
    with pytest.raises(NotKept, match="no longer kept"):
        run.frame(run.earliest - 1)
    with pytest.raises(NotKept):
        run.frame(0)
    pops = run.populations()
    assert len(pops) == run.latest + 1 and pops[-1] == run.frame(run.latest).population


def test_reading_a_computed_period_does_not_wait_for_a_step():
    run = Run("II-4", 0)
    real, release = run.model.step, threading.Event()

    def slow():
        release.wait(5)
        real()

    run.model.step = slow
    stepper = threading.Thread(target=run.frame, args=(1,))
    stepper.start()
    got = []
    reader = threading.Thread(target=lambda: got.append((run.frame(0).t, run.populations())))
    reader.start()
    reader.join(1)
    alive = reader.is_alive()
    release.set()
    stepper.join()
    reader.join()
    assert not alive and got[0][0] == 0 and run.latest == 1


def test_populations_are_the_frames_agent_counts():
    run = Run("VI-1", 0)
    run.frame(15)
    assert run.populations() == [run.frame(t).population for t in range(16)]
    assert run.populations(10) == run.populations()[10:]


def test_extinct_run_keeps_stepping():
    run = Run("VI-2", 3)  # seed index 3 dies out at t = 245 (checked 2026-10-24)
    while run.frame(run.latest).population:
        run.frame(run.latest + LEAD)
    j = run.frame(run.latest + 5).to_json()
    assert j["population"] == 0 and all(v == [] for v in j["agents"].values())
    assert run.populations()[-1] == 0


def test_concurrent_requests_step_each_period_once():
    run, results = Run("IV-14", 0), [None] * 8

    def ask(i):
        results[i] = run.frame(40).to_json()

    threads = [threading.Thread(target=ask, args=(i,)) for i in range(8)]
    for th in threads:
        th.start()
    for th in threads:
        th.join()
    assert run.latest == 40 and all(r == results[0] for r in results)
    m = reference("IV-14", 0, 40)
    assert results[0]["population"] == len(m.agents) and results[0]["agents"]["id"] == [g.id for g in m.agents]


def test_grids_round_trip_exactly():
    m = tiny_model(np.full((3, 3), 4, dtype=int), spice=True)
    m.landscape.sugar[0, 0] = 0.1
    m.landscape.spice[1, 2] = 1 / 3
    put_agent(m, 1, 1, sugar=0.1)
    j = capture(m).to_json()
    assert j["sugar"][0] == 0.1 and j["spice"][1 * 3 + 2] == 1 / 3 and j["agents"]["sugar"] == [0.1]


def test_frames_do_not_share_arrays_with_the_model():
    m = tiny_model(np.full((3, 3), 4, dtype=int))
    f = capture(m)
    m.landscape.sugar[:] = 0
    assert f.to_json()["sugar"] == [4.0] * 9


def test_unknown_and_non_grid_experiments_are_refused():
    others = [i for i, e in EXPERIMENTS.items() if not isinstance(e.config, Config)]
    schelling = next(i for i in others if type(EXPERIMENTS[i].config).__name__ == "SchellingConfig")
    ring = next(i for i in others if type(EXPERIMENTS[i].config).__name__ == "RingConfig")
    for exp_id, k in (("nope", 0), (schelling, 0), (ring, 0), ("II-4", -1)):
        with pytest.raises(ValueError):
            Run(exp_id, k)


def test_catalog_lists_grid_experiments_book_first():
    ids = [e["id"] for e in catalog()]
    assert "TEST-tiny" not in ids and len(ids) == len(set(ids))
    assert all(isinstance(EXPERIMENTS[i].config, Config) for i in ids)
    first_var = next(n for n, i in enumerate(ids) if i.startswith("VAR-"))
    assert ids.index("VI-1") < first_var and all(i.startswith("VAR-") for i in ids[first_var:])
    assert set(catalog()[0]) == {"id", "title", "steps", "seeds"}


def test_info_reports_capacities_and_flags():
    vi1 = Run("VI-1", 0).info()
    assert vi1["tribes"] and vi1["spice"] and vi1["sugar_max"] == vi1["spice_max"] == 4
    assert len(vi1["sugar_capacity"]) == 2500 and len(vi1["spice_capacity"]) == 2500
    assert vi1["experiment"] == "VI-1" and vi1["seed"] == EXPERIMENTS["VI-1"].config.seed
    ii4 = Run("II-4", 0).info()
    assert ii4["spice"] is False and ii4["spice_capacity"] is None and ii4["spice_max"] == 0
    assert ii4["tribes"] is False and ii4["width"] == ii4["height"] == 50
