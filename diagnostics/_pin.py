"""Pin the model defaults a diagnostic was written under, so its tables still regenerate after defaults change.

Epochs, by the commits that changed the defaults:

  A  2026-10-22 before 13:16  founders at age 0, fertility threshold 1.0 (p.55)
  B  2026-10-22 13:16-15:30   founders at ages U[0, max age), threshold 1.0
  C  2026-10-22 15:30 to 10-23 founders at ages U[0, max age), threshold 0.83
  D  from 2026-10-23          founders at ages U[0, max age), threshold 1.0, integer gifts, partners in sight
                              (the current defaults)

Epochs A-C had exact gifts and the four neighbors as partners. Only these settings are pinned; everything else is
today's code. A setting a script passes explicitly still wins: a Config built without it gets the epoch's value,
dataclasses.replace() carries a pinned base's value along, and the VAR- experiments keep every setting their
variant names. Call pin() at module level, so worker processes (spawned on Windows) pin too.
"""
from dataclasses import fields, replace

from experiments.registry import EXPERIMENTS, VARIANTS
from sugarscape.config import Config

EPOCHS = {
    "A": {"founder_ages": "zero", "fertility_threshold": 1.0},
    "B": {"founder_ages": "uniform", "fertility_threshold": 1.0},
    "C": {"founder_ages": "uniform", "fertility_threshold": 0.83},
    "D": {"founder_ages": "uniform", "fertility_threshold": 1.0, "gift_rounding": "down", "mate_contact": "vision"},
}
for _epoch in "ABC":  # rule S as p.55-56 state it, the defaults until 2026-10-23
    EPOCHS[_epoch].update(gift_rounding="exact", mate_contact="neighbors")


def pin(epoch: str) -> None:
    # Fields an older checkout doesn't have yet (founder_ages before 13:16) already behave as the epoch's.
    values = {k: v for k, v in EPOCHS[epoch].items() if k in {f.name for f in fields(Config)}}
    init = getattr(Config.__init__, "_unpinned", Config.__init__)

    def pinned_init(self, *args, **kwargs):
        for name, value in values.items():
            kwargs.setdefault(name, value)
        init(self, *args, **kwargs)

    pinned_init._unpinned = init
    Config.__init__ = pinned_init
    for exp_id, exp in EXPERIMENTS.items():
        if isinstance(exp.config, Config):
            own = VARIANTS[exp_id[4:].split("/")[0]] if exp_id.startswith("VAR-") else {}
            pins = {k: v for k, v in values.items() if k not in own}
            EXPERIMENTS[exp_id] = replace(exp, config=replace(exp.config, **pins))
