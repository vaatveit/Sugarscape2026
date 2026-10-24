# Sugarscape on FLAME GPU 2

A GPU version of the Chapter II rules of Epstein and Axtell's Sugarscape, built with
[FLAME GPU 2](https://flamegpu.com). It is scored against the book with the Python reference model
[Sugarscape2026](https://github.com/vaatveit/Sugarscape2026). The design is in
[docs/superpowers/specs/2026-10-23-phase1-chapter2-gpu-design.md](docs/superpowers/specs/2026-10-23-phase1-chapter2-gpu-design.md).

## Prerequisites

- An NVIDIA GPU with compute capability 7.5 or newer. Builds target 8.9 (RTX 40xx); change
  `CMAKE_CUDA_ARCHITECTURES` in `scripts/build.cmd` for other GPUs.
- The CUDA 13 toolkit (tested with 13.4). `CUDA_PATH` must point at it.
- Visual Studio with the C++ desktop workload. The build uses the CMake and Ninja that ship with
  Visual Studio, run inside `vcvars64`. `scripts/build.cmd` defaults to
  `C:\Program Files\Microsoft Visual Studio\18\Insiders`; set `VS_ROOT` for another install.
- Python 3.14 for the bridge and tests, plus a checkout of Sugarscape2026, found through
  `SUGARSCAPE_ROOT` (default `C:\Projects\Sugarscape2026`).

FLAME GPU 2 is AGPL-3.0 licensed, and so is the template this project started from. FLAME GPU's
usage statistics (telemetry) are switched off in the build and in every script here.

## Build

```bat
scripts\build.cmd
```

This configures `build\` with FLAME GPU's run-time checks on (`FLAMEGPU_SEATBELTS=ON`) and builds
`build\bin\Release\sugarscape_gpu.exe`. The first build downloads and compiles FLAME GPU
`v2.0.0-rc.5`, which takes a while. The benchmark uses a second build with the checks off:

```bat
scripts\build.cmd build-fast OFF
```

The largest world is fixed when building: CMake option `SUGARSCAPE_MAX_CELLS`, default
2500 × 2500 = 6,250,000 sites.

## Tests

```bat
python -m venv .venv
.venv\Scripts\python -m pip install numpy matplotlib pytest
.venv\Scripts\python -m pytest
```
