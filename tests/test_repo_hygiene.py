import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
SOURCE_DIRS = ("sugarscape", "experiments", "replication", "viewer")
SOURCE_SUFFIXES = {".py", ".mjs", ".html", ".css"}


def test_sources_use_lf_line_endings():
    # A Windows write that turned every line ending into CRLF made whole-file diffs of seven files (xl review #3).
    sources = [p for d in SOURCE_DIRS for p in (ROOT / d).rglob("*")
               if p.suffix in SOURCE_SUFFIXES and "__pycache__" not in p.parts]
    assert sources
    assert [str(p.relative_to(ROOT)) for p in sources if b"\r\n" in p.read_bytes()] == []


@pytest.mark.skipif(shutil.which("git") is None or not (ROOT / ".git").exists(), reason="needs a git checkout")
def test_xl_results_are_ignored_like_results():
    for path in ("results/II-4/seed0.csv", "results-xl/II-4/seed0.csv"):
        assert subprocess.run(["git", "check-ignore", "-q", path], cwd=ROOT).returncode == 0, path
