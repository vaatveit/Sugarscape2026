"""The xl fidelity comparison's rules (xl design, section 5), on synthetic seed series."""

import math

from bridge.xl_validate import checkpoints, compare, render_report

STEPS = 20
SPREAD = (-1.2, -0.9, -0.6, -0.3, 0.0, 0.0, 0.3, 0.6, 0.9, 1.2)  # ten seeds; sample sd about 0.73


def _seeds(mean: float, offsets=SPREAD, metric="m") -> list[list[dict]]:
    """One series per offset: every period of the run has the value mean + offset."""
    return [[{"t": t, metric: mean + o} for t in range(STEPS + 1)] for o in offsets]


def _verdicts(gpu, py) -> set[str]:
    return {c.verdict for c in compare("X", gpu, py, STEPS)}


def test_checkpoints():
    assert checkpoints(200) == [20, 50, 100, 200]
    assert checkpoints(300) == [30, 75, 150, 300]
    assert checkpoints(500) == [50, 125, 250, 500]


def test_identical_agrees():
    rows = compare("X", _seeds(100.0), _seeds(100.0), STEPS)
    assert [c.t for c in rows] == checkpoints(STEPS)
    assert all(c.verdict == "agrees" and c.gap_pct == 0 for c in rows)


def test_small_gap_many_spreads_agrees():
    # The user's "close enough": 0.5% apart is many seed spreads apart, and still agrees.
    tiny = tuple(o / 100 for o in SPREAD)
    rows = compare("X", _seeds(100.5, tiny), _seeds(100.0, tiny), STEPS)
    assert all(abs(c.welch_t) > 3 and abs(c.gap_pct - 0.5) < 1e-9 for c in rows)
    assert {c.verdict for c in rows} == {"agrees"}


def test_large_clear_gap_disagrees():
    rows = compare("X", _seeds(102.0), _seeds(100.0), STEPS)
    assert all(abs(c.welch_t) > 3 for c in rows)
    assert {c.verdict for c in rows} == {"disagrees"}


def test_large_noisy_gap_agrees():
    noisy = tuple(5 * o for o in SPREAD)
    rows = compare("X", _seeds(102.0, noisy), _seeds(100.0, noisy), STEPS)
    assert all(abs(c.welch_t) < 3 for c in rows)
    assert {c.verdict for c in rows} == {"agrees"}


def test_no_spread_judged_by_gap():
    flat = (0.0,) * 5
    close = compare("X", _seeds(100.5, flat), _seeds(100.0, flat), STEPS)
    assert all(c.welch_t is None for c in close) and {c.verdict for c in close} == {"agrees"}
    assert _verdicts(_seeds(102.0, flat), _seeds(100.0, flat)) == {"disagrees"}


def test_zero_scale_not_judged():
    assert _verdicts(_seeds(1.0), _seeds(0.0, (0.0,) * 10)) == {"not judged"}


def _with_nan(runs, every_seed=True):
    """The runs with the metric undefined (nan) in every seed, or in the first half of the seeds."""
    n = len(runs) if every_seed else len(runs) // 2
    return [[{**r, "m": math.nan} for r in s] if k < n else s for k, s in enumerate(runs)]


def test_undefined_on_one_side_is_flagged():
    # A metric the GPU leaves undefined where Python has values (or the reverse) is a difference, never hidden.
    for gpu, py in ((_with_nan(_seeds(100.0)), _seeds(100.0)), (_seeds(100.0), _with_nan(_seeds(100.0)))):
        rows = compare("X", gpu, py, STEPS)
        assert {c.verdict for c in rows} == {"undefined on one side"}
    gpu_nan = compare("X", _with_nan(_seeds(100.0)), _seeds(100.0), STEPS)[0]
    assert math.isnan(gpu_nan.gpu_mean) and gpu_nan.py_mean == 100.0  # the side that has a value keeps it
    assert (gpu_nan.n_gpu, gpu_nan.n_py) == (0, 10)


def test_undefined_on_both_sides_is_not_judged():
    assert _verdicts(_with_nan(_seeds(100.0)), _with_nan(_seeds(100.0))) == {"not judged"}


def test_seed_counts_show_partly_undefined_seeds():
    rows = compare("X", _with_nan(_seeds(100.0), every_seed=False), _seeds(100.0), STEPS)
    assert all((c.n_gpu, c.n_py) == (5, 10) for c in rows)


def test_report_shows_one_sided_rows_with_disagreements():
    rows = (compare("A", _seeds(100.0), _seeds(100.0), STEPS)
            + compare("B", _with_nan(_seeds(100.0)), _seeds(100.0), STEPS))
    lines = [line for line in render_report(rows, True, {}, {}).splitlines() if line.startswith("| ")]
    one_sided = [i for i, line in enumerate(lines) if "undefined on one side" in line]
    agree = [i for i, line in enumerate(lines) if line.endswith("| agrees |")]
    assert one_sided and agree and max(one_sided) < min(agree)


def test_report_states_the_no_spread_rule_as_coded():
    # _welch_t has no t only when both sides have no spread.
    assert "no spread on both sides" in render_report([], True, {}, {})


def test_report_lists_disagreements_first():
    rows = compare("A", _seeds(100.0), _seeds(100.0), STEPS) + compare("B", _seeds(102.0), _seeds(100.0), STEPS)
    text = render_report(rows, smoke_ok=True, timings={}, machine={})
    lines = text.splitlines()
    disagree = [i for i, line in enumerate(lines) if "disagrees" in line and line.startswith("|")]
    agree = [i for i, line in enumerate(lines) if "agrees" in line and "disagrees" not in line and line.startswith("|")]
    assert disagree and agree and max(disagree) < min(agree)
    assert "1%" in text and "|t| > 3" in text
