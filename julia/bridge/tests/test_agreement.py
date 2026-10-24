import math

import pytest

from bridge.agreement import (Check, benjamini_hochberg, compare_experiment, eligible, fisher_exact, flag, t_sf,
                              welch, windows)


@pytest.mark.parametrize("t", [0.3, 1.7, 6.0])
def test_t_sf_closed_forms(t):
    assert t_sf(t, 1) == pytest.approx(0.5 - math.atan(t) / math.pi, rel=1e-10)
    assert t_sf(t, 2) == pytest.approx(0.5 - t / (2 * math.sqrt(2 + t * t)), rel=1e-10)
    assert t_sf(-t, 2) == pytest.approx(1 - t_sf(t, 2), rel=1e-12)


def test_t_sf_table_value():
    assert t_sf(2.228138852, 10) == pytest.approx(0.025, abs=1e-7)
    assert t_sf(0.0, 7.5) == pytest.approx(0.5)


def test_welch():
    t, df, p = welch([1, 2, 3, 4, 5], [2, 4, 6, 8, 10])
    assert t == pytest.approx(-3 / math.sqrt(2.5))
    assert df == pytest.approx(6.25 / 1.0625)
    assert p == pytest.approx(2 * t_sf(3 / math.sqrt(2.5), 6.25 / 1.0625))


def test_benjamini_hochberg():
    p = [0.001, 0.008, 0.039, 0.041, 0.042, 0.06, 0.074, 0.205]
    assert benjamini_hochberg(p, 0.05) == [True, True] + [False] * 6
    assert benjamini_hochberg(list(reversed(p)), 0.05) == [False] * 6 + [True, True]
    assert benjamini_hochberg([], 0.01) == []


def test_fisher_exact():
    assert fisher_exact(8, 2, 1, 5) == pytest.approx(0.03496503496503497)
    assert fisher_exact(5, 0, 0, 5) == pytest.approx(2 / 252)
    assert fisher_exact(0, 5, 0, 5) == pytest.approx(1.0)


def test_windows():
    assert windows(500) == [(0, 124), (125, 249), (250, 374), (375, 500)]
    assert windows(5) == [(0, 0), (1, 2), (3, 3), (4, 5)]


def _run(values, metric="population", extra=None):
    return [{"t": t, metric: v, **(extra or {})} for t, v in enumerate(values)]


def _kinds(tests, metric):
    return [x.kind for x in tests if x.metric == metric]


def test_eligibility():
    nan_runs = [_run([math.nan] * 6)]
    assert not eligible("population", nan_runs, nan_runs)
    const = [_run([3.0] * 6)]
    assert not eligible("population", const, const)
    assert eligible("population", const, [_run([3.0, 4.0, 3.0, 3.0, 3.0, 3.0])])


def test_kinds_identical_constant_differs_and_tested():
    py = [_run([5, 5, 5, 5, 5, 5], extra={"x": 1.0}) for _ in range(3)]
    jl = [_run([5, 5, 5, 5, 5, 5], extra={"x": 2.0}) for _ in range(3)]
    jl[0][0]["population"] = 6  # window 0 differs on one Julia seed: eligible, and tested
    tests = compare_experiment("TEST-tiny", py, jl)
    assert _kinds(tests, "population") == ["tested", "identical", "identical", "identical"]
    assert _kinds(tests, "x") == ["constant-differs"] * 4


def test_untestable_after_extinction_and_extinction_contrast():
    alive = [_run([10, 10, 9, 8, 7, 6], extra={"m": float(k)}) for k in range(5)]
    dead = [_run([10, 10, 9, 0, 0, 0], extra={"m": float(k)}) for k in range(5)]
    for run in dead:
        for row in run[3:]:
            row["m"] = math.nan
    tests = compare_experiment("TEST-tiny", alive, dead)
    assert _kinds(tests, "m")[2:] == ["untestable", "untestable"]
    ext = [x for x in tests if x.kind == "extinction"]
    assert len(ext) == 1 and (ext[0].n_py, ext[0].n_jl) == (5, 5)
    assert ext[0].p == pytest.approx(fisher_exact(5, 0, 0, 5))


def test_flag_applies_one_correction():
    tests = [Check("A", "m", 0, "tested", 1e-6, 5, 5, 0, 1, 1),
             Check("A", "m", 1, "tested", 0.5, 5, 5, 0, 0, 1),
             Check("A", "x", 0, "constant-differs", math.nan, 5, 5, 0, 1, 0),
             Check("A", None, None, "extinction", 1e-5, 5, 5, 0, 1, math.nan)]
    flag(tests, 0.01)
    assert [x.flagged for x in tests] == [True, False, True, True]


def test_seed_level_p_uses_fisher_for_outcomes_and_welch_otherwise():
    from bridge.agreement import seed_level_p
    assert seed_level_p([1.0] * 10, [1.0] * 7 + [0.0] * 3) == pytest.approx(fisher_exact(7, 3, 10, 0))
    assert seed_level_p([1, 2, 3, 4, 5], [2, 4, 6, 8, 10]) == pytest.approx(welch([2, 4, 6, 8, 10], [1, 2, 3, 4, 5])[2])
    assert seed_level_p([math.nan, 1.0, 2.0], [1.0, 2.0, 3.0]) == pytest.approx(welch([1.0, 2.0, 3.0], [1.0, 2.0])[2])
    assert math.isnan(seed_level_p([3.0, 3.0], [3.0, 3.0])) and math.isnan(seed_level_p([1.0], [2.0, 3.0]))
