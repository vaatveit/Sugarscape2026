import math
import tomllib

from bridge.export_registry import export_text
from bridge.paths import JULIA_DIR
from experiments.registry import EXPERIMENTS
from experiments.run import fingerprint
from sugarscape.config import Config


def _experiments() -> dict[str, dict]:
    return {e["id"]: e for e in tomllib.loads(export_text())["experiment"]}


def test_registry_is_current():
    assert (JULIA_DIR / "registry.toml").read_text(encoding="utf-8") == export_text()


def test_every_config_experiment_exported():
    ids = [e["id"] for e in tomllib.loads(export_text())["experiment"]]
    assert ids == [i for i, e in EXPERIMENTS.items() if isinstance(e.config, Config)]
    assert len(ids) == 135


def test_values_round_trip():
    exps = _experiments()
    combat = exps["III-11"]["config"]
    assert combat["combat_alpha"] == 2.0 and isinstance(combat["combat_alpha"], float)
    assert combat["initial_blocks"] == [["blue", 0, 0, 20, 20, 200], ["red", 30, 30, 20, 20, 200]]
    assert combat["max_age"] == [60, 100]
    assert "seasons" not in combat
    assert exps["II-1"]["config"]["growback_rate"] == math.inf
    xl = exps["II-4"]["xl_config"]
    assert (xl["width"], xl["initial_population"], xl["vision"], xl["diffusion_passes"]) == (500, 40000, [10, 60], 100)
    assert exps["II-4"]["fingerprint"] == fingerprint("II-4")
    assert exps["II-4"]["xl_fingerprint"] == fingerprint("II-4", xl=True)
    assert exps["VI-1"]["config"]["credit"] == [10, 10.0]
