"""Same-tribe replacement (p.86; spec 2026-10-25-gpu-full-parity, section 4; Part B, Task 1): each newcomer's tags are
redrawn until its tribe is the dead agent's, on every path that makes newcomers."""

import numpy as np
import pytest

from conftest import run_exe
from gpu import run_gpu, write_cfg

EMPTY = np.zeros((20, 20), dtype=int)
TAGS = {"blue": "0" * 11, "red": "1" * 11}
SAME_TRIBE = {"tag_length": "11", "replacement": "true", "max_age": "60,100", "replacement_same_tribe": "true"}
PATHS = {"fast": {}, "turns": {"culture": "true"}, "turns-inheritance": {"culture": "true", "inheritance": "true"}}


def _founders(tribe, **kw):
    # Forty founders on every other site of rows 2-5, none next to another.
    return [{"x": x, "y": y, "vision": 1, "metabolism": 1, "sugar": 50.0, "tags": TAGS[tribe], **kw}
            for y in range(2, 6) for x in range(y % 2, 20, 2)]


def _tribe(tags: str) -> str:
    return "blue" if 2 * tags.count("1") < len(tags) else "red"


@pytest.mark.parametrize("path", ["fast", "turns"])
@pytest.mark.parametrize("tribe", ["blue", "red"])
def test_starved_newcomers_keep_tribe(exe, tmp_path, path, tribe):
    # Everyone starves in period 1 (sugar 1, metabolism 5, no sugar anywhere): forty newcomers, all of the dead's
    # tribe. Without the rule the chance of that is 2^-40.
    gpu = run_gpu(exe, tmp_path, {**SAME_TRIBE, **PATHS[path]}, EMPTY, _founders(tribe, sugar=1.0, metabolism=5))
    assert gpu.returncode == 0, gpu.stderr
    assert len(gpu.agents) == 40
    assert {_tribe(a["tags"]) for a in gpu.agents} == {tribe}


@pytest.mark.parametrize("path", ["fast", "turns", "turns-inheritance"])
def test_old_age_newcomers_keep_tribe(exe, tmp_path, path):
    # Everyone dies of old age in period 1 (max_age 1): forty red newcomers.
    gpu = run_gpu(exe, tmp_path, {**SAME_TRIBE, **PATHS[path]}, EMPTY, _founders("red", max_age=1))
    assert gpu.returncode == 0, gpu.stderr
    assert len(gpu.agents) == 40
    assert {_tribe(a["tags"]) for a in gpu.agents} == {"red"}
    assert {a["age"] for a in gpu.agents} == {0}  # all newcomers


def test_same_tribe_needs_replacement(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, tag_length="11", replacement_same_tribe="true"),
                     "--print-config")
    assert result.returncode == 2
    assert "replacement_same_tribe needs replacement" in result.stderr
