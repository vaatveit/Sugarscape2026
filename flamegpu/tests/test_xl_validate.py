"""The xl fidelity comparison's rules (xl design, section 5), on synthetic seed series."""

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


def test_report_lists_disagreements_first():
    rows = compare("A", _seeds(100.0), _seeds(100.0), STEPS) + compare("B", _seeds(102.0), _seeds(100.0), STEPS)
    text = render_report(rows, smoke_ok=True, timings={}, machine={})
    lines = text.splitlines()
    disagree = [i for i, line in enumerate(lines) if "disagrees" in line and line.startswith("|")]
    agree = [i for i, line in enumerate(lines) if "agrees" in line and "disagrees" not in line and line.startswith("|")]
    assert disagree and agree and max(disagree) < min(agree)
    assert "1%" in text and "|t| > 3" in text
