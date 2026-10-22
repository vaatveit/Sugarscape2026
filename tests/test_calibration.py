from dataclasses import replace

from experiments.registry import CALIBRATED, EXPERIMENTS, VALIDATION
from replication.targets import TARGETS

CAL = [t for t in TARGETS if t.experiment.startswith("CAL-")]


def test_each_setting_runs_every_validation_figure_unchanged_otherwise():
    assert set(CALIBRATED) == {"thr", "share"} and VALIDATION == ("III-1", "III-3", "III-4", "III-5", "VI-2", "VI-3")
    for name, setting in CALIBRATED.items():
        for exp_id in VALIDATION:
            cal, book = EXPERIMENTS[f"CAL-{name}/{exp_id}"], EXPERIMENTS[exp_id]
            assert cal.config == replace(book.config, **setting)
            assert (cal.rules, cal.steps, cal.seeds) == (book.rules, book.steps, book.seeds)


def test_fitted_values_are_frozen():  # fitted to Fig III-1's steady population only (Chapter III record)
    assert CALIBRATED == {"thr": {"fertility_threshold": 0.83}, "share": {"child_share": 0.4975}}


def test_targets_are_mirrored_with_their_baselines():
    book = [t for t in TARGETS if t.experiment in VALIDATION]
    assert len(CAL) == 2 * len(book)
    for t in CAL:
        assert t.experiment in EXPERIMENTS and (t.baseline is None or t.baseline.startswith("CAL-"))
        assert t.baseline is None or t.baseline.split("/")[0] == t.experiment.split("/")[0]


def test_book_experiments_keep_the_book_rule():
    for exp_id in VALIDATION:
        c = EXPERIMENTS[exp_id].config
        assert (c.fertility_threshold, c.child_share) == (1.0, 0.5)
