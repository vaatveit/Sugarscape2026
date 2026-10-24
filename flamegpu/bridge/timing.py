"""docs/xl.md's timing files for GPU runs: timing.csv (one row per seed) and machine.txt, in the Python runner's layout."""

import csv
import platform
import subprocess
from pathlib import Path

from bridge.paths import subprocess_env
from experiments.run import TIMING_COLUMNS


def timing_row(seed: int, data: dict) -> dict:
    """One timing.csv row, in TIMING_COLUMNS order, from a seed's --timing JSON."""
    values = {"seed": seed, **{k: data[k] for k in TIMING_COLUMNS if k != "seed"}}
    return {k: values[k] for k in TIMING_COLUMNS}


def write_timing_csv(path: Path, rows: list[dict]) -> None:
    with Path(path).open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=TIMING_COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow({k: repr(v) for k, v in row.items()})


def _command(*args: str) -> str | None:
    try:
        result = subprocess.run(list(args), capture_output=True, text=True, env=subprocess_env(), timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def machine_note(exe: Path, jobs: int) -> str:
    """Where and how the timings were taken: the program's --version facts, the driver, the platform, and jobs."""
    version = _command(str(exe), "--version")
    lines = version.splitlines() if version else ["flamegpu = unknown"]
    driver = _command("nvidia-smi", "--query-gpu=driver_version", "--format=csv,noheader")
    lines += [f"driver = {driver.splitlines()[0] if driver else 'unknown'}", f"exe = {exe}",
              f"platform = {platform.platform()}", f"processor = {platform.processor() or 'unknown'}",
              f"jobs = {jobs}", "note = every seed is a fresh process, so every setup includes starting CUDA"]
    if jobs > 1:
        lines.append(f"note = timings taken with --jobs {jobs} share the GPU")
    return "\n".join(lines) + "\n"
