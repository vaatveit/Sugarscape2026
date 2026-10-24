"""Where things are: the Python Sugarscape project, the GPU executable, and the subprocess environment."""

import os
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# The Python reference model, read but never written (design: Non-goals).
DEFAULT_SUGARSCAPE_ROOT = r"C:\Projects\Sugarscape2026"


def default_sugarscape_root(project_root: Path) -> Path:
    """The parent folder when this project is a subfolder of the Python project, else the standalone default."""
    parent = Path(project_root).parent
    if (parent / "sugarscape" / "config.py").is_file():
        return parent
    return Path(DEFAULT_SUGARSCAPE_ROOT)


SUGARSCAPE_ROOT = Path(os.environ.get("SUGARSCAPE_ROOT", default_sugarscape_root(PROJECT_ROOT)))
if str(SUGARSCAPE_ROOT) not in sys.path:
    sys.path.insert(0, str(SUGARSCAPE_ROOT))

# The seatbelts-on build used by tests and validation; SUGARSCAPE_GPU_EXE overrides it.
EXE = Path(os.environ.get("SUGARSCAPE_GPU_EXE", PROJECT_ROOT / "build" / "bin" / "Release" / "sugarscape_gpu.exe"))
FAST_EXE = PROJECT_ROOT / "build-fast" / "bin" / "Release" / "sugarscape_gpu.exe"

BUILD_COMMAND = r"scripts\build.cmd"

# The program needs the CUDA runtime DLLs (nvrtc, cudart); a shell started before CUDA was installed lacks them.
CUDA_PATH = Path(os.environ.get("CUDA_PATH", r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.4"))


def subprocess_env() -> dict[str, str]:
    """os.environ with CUDA's DLL folder on PATH (bin\\x64 in CUDA 13) and FLAME GPU telemetry off."""
    path = os.environ.get("PATH", "")
    cuda_bin = str(CUDA_PATH / "bin" / "x64")
    if cuda_bin.lower() not in path.lower():
        path = cuda_bin + os.pathsep + path
    return {**os.environ, "PATH": path, "FLAMEGPU_SHARE_USAGE_STATISTICS": "OFF"}
