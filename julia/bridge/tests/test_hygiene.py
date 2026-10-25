"""Text files of the Julia port, and the README, use LF line endings (tests/test_repo_hygiene.py does sugarscape/)."""

import subprocess

from bridge.paths import REPO_ROOT

TEXT = (".jl", ".py", ".md", ".toml", ".ini")


def test_julia_sources_and_readme_use_lf_line_endings():
    tracked = subprocess.run(["git", "ls-files", "julia", "README.md"], cwd=REPO_ROOT, capture_output=True,
                             text=True, check=True).stdout.split()
    crlf = [f for f in tracked if f.endswith(TEXT) and b"\r\n" in (REPO_ROOT / f).read_bytes()]
    assert crlf == []
