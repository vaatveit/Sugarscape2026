"""Where things are: the Python Sugarscape project, the GPU executable, and the subprocess environment."""

import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# The Python reference model, read but never written (design: Non-goals).
SUGARSCAPE_ROOT = Path(os.environ.get("SUGARSCAPE_ROOT", r"C:\Projects\Sugarscape2026"))
if str(SUGARSCAPE_ROOT) not in sys.path:
    sys.path.insert(0, str(SUGARSCAPE_ROOT))

# The seatbelts-on build used by tests and validation; SUGARSCAPE_GPU_EXE overrides it.
EXE = Path(os.environ.get("SUGARSCAPE_GPU_EXE", PROJECT_ROOT / "build" / "bin" / "Release" / "sugarscape_gpu.exe"))
FAST_EXE = PROJECT_ROOT / "build-fast" / "bin" / "Release" / "sugarscape_gpu.exe"

BUILD_COMMAND = r"scripts\build.cmd"


def subprocess_env() -> dict[str, str]:
    """os.environ with FLAME GPU telemetry off."""
    return {**os.environ, "FLAMEGPU_SHARE_USAGE_STATISTICS": "OFF"}
