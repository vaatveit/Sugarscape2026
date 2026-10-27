import pytest

from conftest import run_exe
from gpu import SUGAR_MAP, parse_printed, write_cfg, write_map

OPTIONS = ("--config", "--out", "--init", "--metrics-every", "--dump-agents", "--dump-landscape", "--dump-at",
           "--tile", "--timing", "--check", "--version")


def test_help_lists_options(exe):
    result = run_exe(exe, "--help")
    assert result.returncode == 0, result.stderr
    for option in OPTIONS:
        assert option in result.stdout


def test_no_arguments_is_usage_error(exe):
    result = run_exe(exe)
    assert result.returncode == 2
    assert "--config" in result.stderr


def test_unknown_option_is_usage_error(exe):
    result = run_exe(exe, "--frobnicate")
    assert result.returncode == 2
    assert "--frobnicate" in result.stderr


# --- Task 2: run.cfg, maps, tiling ------------------------------------------------------------


def _error(result) -> str:
    """The error message: stderr's first line (the usage text follows it)."""
    return result.stderr.splitlines()[0] if result.stderr else ""


def _capacity_sum() -> int:
    return sum(int(v) for line in SUGAR_MAP.read_text().splitlines() for v in line.split())


def test_print_config_round_trips(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path), "--print-config")
    assert result.returncode == 0, result.stderr
    printed = parse_printed(result.stdout)
    assert printed["width"] == "50"
    assert printed["growback_rate"] == "1"
    assert printed["max_age"] == ""
    assert printed["map_cells"] == "2500"
    assert int(printed["map_capacity_sum"]) == _capacity_sum()


def test_unknown_key_is_rejected(exe, tmp_path):
    cfg = write_cfg(tmp_path)
    cfg.write_text(cfg.read_text() + "colour = red\n")
    result = run_exe(exe, "--config", cfg, "--print-config")
    assert result.returncode == 2
    assert "colour" in _error(result)


def test_unsupported_feature_key_is_rejected(exe, tmp_path):
    cfg = write_cfg(tmp_path)
    cfg.write_text(cfg.read_text() + "sugar_map = sugar-map.txt\n")  # run.cfg names the map by its path
    result = run_exe(exe, "--config", cfg, "--print-config")
    assert result.returncode == 2
    assert "sugar_map" in _error(result)


def test_vision_too_large_is_rejected(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, vision="1,25"), "--print-config")
    assert result.returncode == 2
    assert "vision" in _error(result)


def test_replacement_needs_max_age(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, replacement="true"), "--print-config")
    assert result.returncode == 2
    assert "max_age" in _error(result)


def test_bad_map_is_rejected(exe, tmp_path):
    good = [[1] * 50 for _ in range(50)]
    cases = {
        "short.txt": good[:49],
        "token.txt": good[:10] + [[1] * 49 + ["x"]] + good[11:],
        "ragged.txt": good[:10] + [[1] * 49] + good[11:],
    }
    for name, rows in cases.items():
        map_path = write_map(tmp_path / name, rows)
        result = run_exe(exe, "--config", write_cfg(tmp_path, map=str(map_path)), "--print-config")
        assert result.returncode == 2, name
        assert name in _error(result), name


def test_tile_scales_world(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path), "--tile", "2", "--print-config")
    assert result.returncode == 0, result.stderr
    printed = parse_printed(result.stdout)
    assert printed["width"] == "100"
    assert printed["height"] == "100"
    assert printed["initial_population"] == "1600"
    assert printed["map_cells"] == "10000"
    assert int(printed["map_capacity_sum"]) == 4 * _capacity_sum()


def test_world_at_max_cells_is_accepted(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path), "--tile", "50", "--print-config")
    assert result.returncode == 0, result.stderr
    printed = parse_printed(result.stdout)
    assert printed["width"] == "2500"
    assert printed["map_cells"] == "6250000"


def test_world_over_max_cells_is_rejected(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path), "--tile", "51", "--print-config")
    assert result.returncode == 2
    assert "SUGARSCAPE_MAX_CELLS" in _error(result)


# --- Task 10: timing ----------------------------------------------------------------------------


@pytest.mark.parametrize("build", ["build", "build-fast"])
def test_timing_json(exe, tmp_path, build):
    import json

    from bridge.paths import FAST_EXE

    program = exe if build == "build" else FAST_EXE
    if not program.exists():
        pytest.skip(f"no {program}")
    timing, metrics = tmp_path / "t.json", tmp_path / "m.csv"
    result = run_exe(program, "--config", write_cfg(tmp_path, steps="20"), "--timing", timing, "--out", metrics)
    assert result.returncode == 0, result.stderr
    data = json.loads(timing.read_text())
    # docs/xl.md's measures join the keys bridge.bench reads, which stay.
    assert set(data) >= {"cells", "agents_initial", "steps", "simulate_seconds", "step_seconds_mean", "setup_s",
                         "stepping_s", "metrics_s", "periods", "agents_start", "agents_end"}
    assert data["steps"] == 20 and data["cells"] == 2500 and data["agents_initial"] == 400
    assert data["step_seconds_mean"] > 0
    assert data["periods"] == 20 and data["agents_start"] == 400
    assert data["agents_end"] == int(metrics.read_text().splitlines()[-1].split(",")[1])  # the population column
    assert data["setup_s"] > 0 and data["stepping_s"] > 0 and data["metrics_s"] > 0
    assert data["stepping_s"] == pytest.approx(data["step_seconds_mean"] * 20, rel=1e-6)
    # The periods are most of the simulation's wall-clock time; only initialisation is left out.
    assert 0.2 * data["simulate_seconds"] <= data["step_seconds_mean"] * data["steps"] <= data["simulate_seconds"]


@pytest.mark.parametrize("build", ["build", "build-fast"])
def test_version(exe, build):
    from bridge.paths import FAST_EXE

    program = exe if build == "build" else FAST_EXE
    if not program.exists():
        pytest.skip(f"no {program}")
    result = run_exe(program, "--version")
    assert result.returncode == 0, result.stderr
    info = parse_printed(result.stdout)
    assert info["flamegpu"].startswith("2.0.0-rc.5")
    assert info["seatbelts"] == ("on" if build == "build" else "off")
    assert info["max_cells"] == "6250000"
    assert info["max_tag_bits"] == "63"  # spec 2026-10-25-gpu-full-parity, section 5
    assert info["max_friends"] == "5" and info["max_sight_looks"] == "64" and info["uid_capacity"] == "16777216"
    assert info["loans_per_cell"] == "2" and info["max_heirs"] == "32"  # plan 2026-10-26-gpu-parity-part-c, Tasks 6-7
    assert info["gpu"] != "" and info["cuda_runtime"] != ""


def test_version_output_is_never_lost(exe):
    # --version starts CUDA; its output was once lost in about 1 run in 4 (exit 0, empty stdout) when CUDA's
    # teardown ended the process before stdout was flushed.
    outputs = [run_exe(exe, "--version").stdout for _ in range(60)]
    assert all("flamegpu = " in out for out in outputs), f"{sum('flamegpu = ' not in o for o in outputs)} of 60 lost"


def test_max_age_below_one_is_rejected(exe, tmp_path):
    # Python cannot draw a founder age from U[0, 0); an agent must be able to live at least one period.
    result = run_exe(exe, "--config", write_cfg(tmp_path, max_age="0,5"), "--print-config")
    assert result.returncode == 2
    assert "max_age" in _error(result)


# --- xl: diffusion_passes ------------------------------------------------------------------------


def test_diffusion_passes_defaults_to_one(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path), "--print-config")
    assert result.returncode == 0, result.stderr
    assert parse_printed(result.stdout)["diffusion_passes"] == "1"


def test_diffusion_passes_is_read(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, diffusion_passes="100"), "--print-config")
    assert result.returncode == 0, result.stderr
    assert parse_printed(result.stdout)["diffusion_passes"] == "100"


def test_diffusion_passes_below_one_is_rejected(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, diffusion_passes="0"), "--print-config")
    assert result.returncode == 2
    # The validation message, not the unknown-key one that also names the key.
    assert "diffusion_passes" in _error(result) and ">= 1" in _error(result)


# --- xl: look_stride -----------------------------------------------------------------------------


def test_look_stride_defaults_to_one(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path), "--print-config")
    assert result.returncode == 0, result.stderr
    assert parse_printed(result.stdout)["look_stride"] == "1"


def test_look_stride_is_read(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, look_stride="2", vision="2,6"), "--print-config")
    assert result.returncode == 0, result.stderr
    assert parse_printed(result.stdout)["look_stride"] == "2"


def test_look_stride_below_one_is_rejected(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, look_stride="0"), "--print-config")
    assert result.returncode == 2
    assert "look_stride" in _error(result) and ">= 1" in _error(result)


def test_vision_not_in_whole_strides_is_rejected(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, look_stride="2", vision="1,6"), "--print-config")
    assert result.returncode == 2
    # The validation message, not the unknown-key one.
    assert "look_stride" in _error(result) and "whole look strides" in _error(result)


# --- Part A (spec 2026-10-25-gpu-full-parity), Task 1: Chapter III fields ----------------------------------

CH3_OFF_DEFAULT = {
    "sex": "true", "fertility_start": "11,14", "female_fertility_end": "30,40", "male_fertility_end": "40,50",
    "inheritance": "true", "tag_length": "11", "culture": "true",
    "initial_blocks": "blue,0,0,20,20,270;red,30,30,20,20,270", "fertility_threshold": "0.74", "child_share": "0.4975",
    "mate_contact": "neighbors", "child_gift": "capped", "child_threshold": "redraw", "gift_rounding": "exact",
    "max_age": "60,100",
}


def test_chapter3_keys_round_trip(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **CH3_OFF_DEFAULT), "--print-config")
    assert result.returncode == 0, result.stderr
    printed = parse_printed(result.stdout)
    for key, value in CH3_OFF_DEFAULT.items():
        assert printed[key] == value, key


@pytest.mark.parametrize("overrides, named", [
    ({"tag_length": "10"}, "tag_length"),
    ({"tag_length": "65"}, "63"),
    ({"culture": "true"}, "tag"),
    ({"tag_length": "11", "initial_blocks": "blue,40,40,20,20,10"}, "block"),
    ({"tag_length": "11", "initial_blocks": "blue,0,0,2,2,5"}, "block"),
    ({"tag_length": "11", "initial_blocks": "green,0,0,20,20,10"}, "tribe"),
    ({"fertility_threshold": "0"}, "fertility_threshold"),
    ({"child_share": "1.5"}, "child_share"),
    ({"mate_contact": "touch"}, "mate_contact"),
    ({"child_gift": "all"}, "child_gift"),
    ({"child_threshold": "none"}, "child_threshold"),
    ({"gift_rounding": "up"}, "gift_rounding"),
    ({"fertility_start": "15,12"}, "fertility_start"),
])
def test_chapter3_validation(exe, tmp_path, overrides, named):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **overrides), "--print-config")
    assert result.returncode == 2
    assert named in _error(result)


def test_initial_blocks_with_tile_rejected(exe, tmp_path):
    cfg = write_cfg(tmp_path, tag_length="11", initial_blocks="blue,0,0,20,20,10")
    result = run_exe(exe, "--config", cfg, "--tile", "2", "--print-config")
    assert result.returncode == 2
    assert "initial_blocks" in _error(result)


@pytest.mark.parametrize("overrides, named", [
    ({"tag_length": "11", "combat_alpha": "-1"}, "combat_alpha must be >= 0"),
    ({"combat_alpha": "2"}, "need cultural tags"),
])
def test_combat_alpha_validated(exe, tmp_path, overrides, named):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **overrides), "--print-config")
    assert result.returncode == 2
    assert named in _error(result)


# --- Chapter IV (spec 2026-10-25-gpu-full-parity, Part C) ---------------------------------------------------------

CHAPTER4 = {"spice": "true", "spice_metabolism": "2,3", "spice_endowment": "7,9", "foresight": "0,10",
            "tag_length": "3", "cultural_preferences": "true", "trade": "true", "trade_rounding": "down", "sex": "true",
            "credit": "10,10.0"}


def test_chapter4_fields_round_trip(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **CHAPTER4), "--print-config")
    assert result.returncode == 0, result.stderr
    printed = parse_printed(result.stdout)
    assert {k: printed[k] for k in CHAPTER4} == {**CHAPTER4, "credit": "10,10"}  # 10.0 prints as Python's repr of 10


@pytest.mark.parametrize("overrides, named", [
    ({"trade": "true"}, "need the second commodity"),
    ({"spice": "true", "cultural_preferences": "true"}, "cultural preferences need cultural tags"),
    ({"spice": "true", "tag_length": "1", "combat_alpha": "2"}, "combat is defined for sugar only"),
    ({"credit": "10,10.0"}, "it needs sex=True"),
    ({"sex": "true", "tag_length": "1", "combat_alpha": "2", "credit": "10,10.0"}, "combat movement doesn't record"),
    ({"sex": "true", "credit": "0,10.0"}, "credit duration must be >= 1"),
    ({"trade_rounding": "up"}, "trade_rounding must be one of"),
], ids=["trade-no-spice", "prefs-no-tags", "spice-combat", "credit-no-sex", "credit-combat", "credit-d0", "bad-rounding"])
def test_chapter4_validated(exe, tmp_path, overrides, named):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **overrides), "--print-config")
    assert result.returncode == 2
    assert named in _error(result)


# --- Chapter V (spec 2026-10-25-gpu-full-parity, Part D) ---------------------------------------------------------

CHAPTER5 = {"disease_list": "25", "diseases_per_agent": "10", "disease_length": "2,9", "immune_length": "40",
            "disease_fee": "1.5"}


def test_chapter5_fields_round_trip(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **CHAPTER5), "--print-config")
    assert result.returncode == 0, result.stderr
    printed = parse_printed(result.stdout)
    assert {k: printed[k] for k in CHAPTER5} == CHAPTER5


@pytest.mark.parametrize("overrides, named", [
    ({"disease_list": "-1"}, "disease_list and diseases_per_agent must be >= 0"),
    ({"disease_list": "3", "diseases_per_agent": "4"}, "cannot offer 4 distinct diseases from a list of 3"),
    ({"disease_length": "0,5"}, "must be a range starting at >= 1"),
    ({"disease_length": "1,50", "immune_length": "50"}, "diseases must be shorter than immune systems"),
    ({"disease_fee": "-1"}, "disease_fee must be >= 0"),
    ({"disease_list": "1", "immune_length": "65"}, "the GPU holds at most 64 immune bits"),
    ({"disease_list": "65"}, "the GPU holds at most 64 diseases"),
], ids=["negative", "too-many", "length0", "too-long", "fee", "immune65", "list65"])
def test_chapter5_validated(exe, tmp_path, overrides, named):
    result = run_exe(exe, "--config", write_cfg(tmp_path, **overrides), "--print-config")
    assert result.returncode == 2
    assert named in _error(result)


def test_gpu_limits_only_with_disease(exe, tmp_path):
    # Python accepts any immune_length without disease; so does the GPU.
    result = run_exe(exe, "--config", write_cfg(tmp_path, immune_length="80"), "--print-config")
    assert result.returncode == 0, result.stderr


def test_disease_run_refused_for_now(exe, tmp_path):
    result = run_exe(exe, "--config", write_cfg(tmp_path, disease_list="1", steps="1"))
    assert result.returncode == 2
    assert "not on the GPU yet" in _error(result)


# --- The deferred minors (Parts A and B) --------------------------------------------------------------------------

def _still(**kw):
    return {"x": 2, "y": 2, "vision": 1, "metabolism": 1, "sugar": 10.0, "age": 0, "max_age": None, **kw}


@pytest.mark.parametrize("cfg, size, agents, named", [
    # Partners in sight look vision / look_stride sites along each line: at most 64 (MAX_SIGHT_LOOKS).
    ({"sex": "true", "mate_contact": "vision"}, 140, [_still(vision=65, sex="F", fertility_start=12, fertility_end=50)],
     "partners in sight"),
    ({"tag_length": "5"}, 50, [_still(tags="0000000")], "tags"),
    ({}, 50, [_still(), _still(x=5, parent_a=5)], "parent"),
    ({}, 50, [_still(), _still(x=5, friends="7:0")], "friend"),
])
def test_init_agents_within_limits(exe, tmp_path, cfg, size, agents, named):
    # --init agents meet the same limits as drawn ones, with a message naming the line.
    import numpy as np
    from gpu import run_gpu

    dump = run_gpu(exe, tmp_path, cfg, np.zeros((size, size), dtype=int), agents, steps=1)
    assert dump.returncode == 2, dump.stderr
    assert named in dump.stderr and "line" in dump.stderr, dump.stderr


@pytest.mark.parametrize("value", ["0", "4294967296", "-5", "1e6"])
def test_uid_capacity_out_of_range(exe, tmp_path, value):
    # Uids are 32-bit: --uid-capacity takes 1 .. 2^32 - 1 (a usage error, exit 2, otherwise). A capacity the device
    # cannot hold stops the run with exit 5 naming --uid-capacity (store.cu); Windows pages device memory, so no test
    # here can force that.
    result = run_exe(exe, "--config", write_cfg(tmp_path, steps="1"), "--uid-capacity", value)
    assert result.returncode == 2, result.stderr
    assert "--uid-capacity expects a whole number from 1 to 4294967295" in result.stderr
