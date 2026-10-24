"""Runs the viewer's JavaScript encoding tests (tests/js) under Node's built-in test runner."""

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


def test_encoding_module_passes_its_node_tests():
    node = shutil.which("node")
    if node is None:
        pytest.skip("node is not installed")
    done = subprocess.run([node, "--test", "tests/js/*.test.mjs"], cwd=ROOT, capture_output=True, text=True)
    assert done.returncode == 0, done.stdout + done.stderr
