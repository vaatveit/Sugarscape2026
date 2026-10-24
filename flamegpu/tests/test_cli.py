import pytest

from conftest import run_exe
from gpu import SUGAR_MAP, parse_printed, write_cfg, write_map

OPTIONS = ("--config", "--out", "--init", "--metrics-every", "--dump-agents", "--dump-landscape", "--dump-at",
           "--tile", "--timing", "--check")


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
    cfg.write_text(cfg.read_text() + "sex = true\n")
    result = run_exe(exe, "--config", cfg, "--print-config")
    assert result.returncode == 2
    assert "sex" in _error(result)


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
    timing = tmp_path / "t.json"
    result = run_exe(program, "--config", write_cfg(tmp_path, steps="20"), "--timing", timing)
    assert result.returncode == 0, result.stderr
    data = json.loads(timing.read_text())
    assert set(data) == {"cells", "agents_initial", "steps", "simulate_seconds", "step_seconds_mean"}
    assert data["steps"] == 20 and data["cells"] == 2500 and data["agents_initial"] == 400
    assert data["step_seconds_mean"] > 0
    # The periods are most of the simulation's wall-clock time; only initialisation is left out.
    assert 0.2 * data["simulate_seconds"] <= data["step_seconds_mean"] * data["steps"] <= data["simulate_seconds"]


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
