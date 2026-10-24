from dataclasses import replace

from experiments.registry import EXPERIMENTS, VALIDATION, VARIANTS
from experiments.run import fingerprint
from replication.targets import TARGETS

VAR = [t for t in TARGETS if t.experiment.startswith("VAR-")]


def test_each_variant_runs_every_validation_figure_unchanged_otherwise():
    assert set(VARIANTS) == {"book", "share", "c1c3fit", "intgift", "intgiftc1", "fit83"} and VALIDATION == ("III-1", "III-3", "III-4", "III-5", "VI-2", "VI-3")
    for name, setting in VARIANTS.items():
        for exp_id in VALIDATION:
            var, default = EXPERIMENTS[f"VAR-{name}/{exp_id}"], EXPERIMENTS[exp_id]
            assert var.config == replace(default.config, **setting)
            assert (var.rules, var.steps, var.seeds) == (default.rules, default.steps, default.seeds)


def test_variant_settings_are_frozen():  # VAR-book is p.55 as written; VAR-share, VAR-c1c3fit as fitted;
    # VAR-intgift is p.55 with integer gifts, VAR-intgiftc1 adds partners in sight (the default since 2026-10-23);
    # VAR-fit83 is the former default (Chapter III record). Each names its threshold, rounding and contact.
    book = {"gift_rounding": "exact", "mate_contact": "neighbors"}
    assert VARIANTS == {"book": {"fertility_threshold": 1.0, **book},
                        "share": {"fertility_threshold": 1.0, "child_share": 0.4975, **book},
                        "c1c3fit": {"fertility_threshold": 0.74, "mate_contact": "vision", "child_gift": "capped",
                                    "child_threshold": "redraw", "gift_rounding": "exact"},
                        "intgift": {"fertility_threshold": 1.0, "gift_rounding": "down", "mate_contact": "neighbors"},
                        "intgiftc1": {"fertility_threshold": 1.0, "gift_rounding": "down", "mate_contact": "vision"},
                        "fit83": {"fertility_threshold": 0.83, **book}}
    assert not any(e.startswith("CAL-") for e in EXPERIMENTS)


def test_targets_are_mirrored_with_their_baselines():
    default = [t for t in TARGETS if t.experiment in VALIDATION]
    assert len(VAR) == len(VARIANTS) * len(default)
    for t in VAR:
        assert t.experiment in EXPERIMENTS and (t.baseline is None or t.baseline.startswith("VAR-"))
        assert t.baseline is None or t.baseline.split("/")[0] == t.experiment.split("/")[0]


def test_default_experiments_use_integer_gifts_and_partners_in_sight():  # user decision 2026-10-23
    for exp_id in VALIDATION:
        c = EXPERIMENTS[exp_id].config
        assert (c.fertility_threshold, c.child_share, c.gift_rounding, c.mate_contact) == (1.0, 0.5, "down", "vision")
    assert EXPERIMENTS["VAR-intgiftc1/III-1"].config == EXPERIMENTS["III-1"].config


def test_fingerprints_name_rule_s_options_only_when_they_depart_from_the_defaults():
    assert "mate_contact" not in fingerprint("III-1") and "gift_rounding" not in fingerprint("III-1")
    assert "mate_contact='neighbors'" in fingerprint("VAR-book/III-1")
    assert "gift_rounding='exact'" in fingerprint("VAR-book/III-1") and "gift_rounding" not in fingerprint("VAR-intgift/III-1")
