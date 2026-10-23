"""Pin the model defaults a diagnostic was written under, so its tables still regenerate after defaults change.

Epochs, by the commits that changed the defaults (2026-10-22):

  A  before 13:16  founders at age 0, fertility threshold 1.0 (p.55)
  B  13:16-15:30   founders at ages U[0, max age), threshold 1.0
  C  from 15:30    founders at ages U[0, max age), threshold 0.83 (the current defaults)

Only these two settings are pinned; everything else is today's code. A setting a script passes explicitly
still wins: a Config built without it gets the epoch's value, dataclasses.replace() carries a pinned base's
value along, and the VAR- experiments keep the threshold they set. Call pin() at module level, so worker
processes (spawned on Windows) pin too.
"""
from dataclasses import fields, replace

from experiments.registry import EXPERIMENTS
from sugarscape.config import Config

EPOCHS = {
    "A": {"founder_ages": "zero", "fertility_threshold": 1.0},
    "B": {"founder_ages": "uniform", "fertility_threshold": 1.0},
    "C": {"founder_ages": "uniform", "fertility_threshold": 0.83},
}


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
            pins = {k: v for k, v in values.items() if not (exp_id.startswith("VAR-") and k == "fertility_threshold")}
            EXPERIMENTS[exp_id] = replace(exp, config=replace(exp.config, **pins))
