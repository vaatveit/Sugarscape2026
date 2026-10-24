import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from bridge.paths import BUILD_COMMAND, EXE, subprocess_env  # noqa: E402


@pytest.fixture(scope="session")
def exe() -> Path:
    if not EXE.exists():
        pytest.skip(f"build first: {BUILD_COMMAND} (no {EXE})")
    return EXE


def run_exe(exe: Path, *args: str) -> subprocess.CompletedProcess:
    """Run the program, capturing text output, with telemetry off."""
    return subprocess.run([str(exe), *map(str, args)], capture_output=True, text=True, env=subprocess_env(),
                          timeout=600)
