"""Finding the Python Sugarscape project: standalone checkout or the GPU project as its subfolder."""

from pathlib import Path

from bridge.paths import DEFAULT_SUGARSCAPE_ROOT, default_sugarscape_root


def test_parent_with_sugarscape_package_is_used(tmp_path):
    (tmp_path / "sugarscape").mkdir()
    (tmp_path / "sugarscape" / "config.py").write_text("")
    project = tmp_path / "flamegpu"
    project.mkdir()
    assert default_sugarscape_root(project) == tmp_path


def test_standalone_checkout_falls_back(tmp_path):
    project = tmp_path / "FlameGPU"
    project.mkdir()
    assert default_sugarscape_root(project) == Path(DEFAULT_SUGARSCAPE_ROOT)
