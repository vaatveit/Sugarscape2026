"""Run registered experiments on the GPU: one seed{k}.csv per seed, as the Python project's experiments.run writes.

Usage: python -m bridge.gpu_run <id-or-prefix> [--seeds N] [--jobs J] [--out DIR] [--xl] [--exe PATH]
A prefix such as "II" runs every "II-..." id; "II-5" runs every "II-5/..." id. --xl runs the 500x500 version
(docs/xl.md) into results-gpu-xl/. Each run also writes timing.csv and machine.txt.
"""

import argparse
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from bridge.paths import EXE, subprocess_env
from bridge.config_cfg import UnsupportedFeature, config_to_cfg, unsupported_features
from bridge.timing import machine_note, timing_row, write_timing_csv
from experiments.registry import EXPERIMENTS
from experiments.run import experiment_config, fingerprint, result_dir

GPU_FINGERPRINT = "gpu-phase2\n"  # 2026-10-25: movement and neighbour counts in Python's order
# Replacement moved to the device (spec 2026-10-25): its random stream changed, so results made before are stale.
REPLACEMENT_FINGERPRINT = "replacement: device\n"


def gpu_fingerprint(exp_id: str, xl: bool = False) -> str:
    """The fingerprint.txt of the GPU's results for an experiment (or its xl version)."""
    extra = REPLACEMENT_FINGERPRINT if experiment_config(exp_id, xl).replacement else ""
    return GPU_FINGERPRINT + extra + fingerprint(exp_id, xl)


def default_out_gpu(xl: bool) -> Path:
    """xl results never mix with the regular results-gpu/, as Python's results-xl/ never mixes with results/."""
    return Path("results-gpu-xl") if xl else Path("results-gpu")


def matching_ids(arg: str, ids) -> list[str]:
    """The id itself, else its sweep points ("II-5" -> "II-5/..."), else a chapter ("II" -> "II-...")."""
    ids = list(ids)
    if arg in ids:
        return [arg]
    sweep = [i for i in ids if i.startswith(arg + "/")]
    return sweep or [i for i in ids if i.startswith(arg + "-")]


def _run_seed(exe: Path, folder: Path, cfg_text: str, k: int) -> dict:
    """Run seed k; returns its --timing JSON."""
    cfg = folder / f"run{k}.cfg"
    cfg.write_text(cfg_text, encoding="utf-8")
    timing = folder / f"timing{k}.json"
    result = subprocess.run([str(exe), "--config", str(cfg), "--out", str(folder / f"seed{k}.csv"),
                             "--timing", str(timing)], capture_output=True, text=True, env=subprocess_env())
    if result.returncode != 0:
        raise RuntimeError(f"{folder.name} seed {k}: exit {result.returncode}: {result.stderr.strip()}")
    return json.loads(timing.read_text(encoding="utf-8"))


def run_experiment_gpu(exp_id: str, seeds: int | None = None, jobs: int = 1, out_dir: Path | None = None,
                       exe: Path = EXE, xl: bool = False) -> list[Path]:
    """Run seeds base + 0 .. base + n-1 of one experiment (or its xl version); returns the seed CSV paths."""
    exp = EXPERIMENTS[exp_id]
    config = experiment_config(exp_id, xl)
    n = seeds if seeds is not None else exp.seeds
    folder = result_dir(exp_id, Path(out_dir) if out_dir is not None else default_out_gpu(xl))
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("seed*.csv"):
        old.unlink()
    texts = [config_to_cfg(config, steps=exp.steps, seed=config.seed + k) for k in range(n)]
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        timings = list(pool.map(lambda k: _run_seed(Path(exe), folder, texts[k], k), range(n)))
    (folder / "fingerprint.txt").write_text(gpu_fingerprint(exp_id, xl), encoding="utf-8")
    write_timing_csv(folder / "timing.csv", [timing_row(k, t) for k, t in enumerate(timings)])
    (folder / "machine.txt").write_text(machine_note(Path(exe), jobs), encoding="utf-8")
    return [folder / f"seed{k}.csv" for k in range(n)]


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("id")
    parser.add_argument("--seeds", type=int, default=None)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--out", type=Path, default=None, help="default: results-gpu/, or results-gpu-xl/ with --xl")
    parser.add_argument("--xl", action="store_true", help="run the 500x500 xl version (docs/xl.md)")
    parser.add_argument("--exe", type=Path, default=EXE, help="the program (default: the seatbelts-on build)")
    args = parser.parse_args(argv)
    ids = matching_ids(args.id, EXPERIMENTS)
    if not ids:
        parser.error(f"no experiment matches {args.id!r}")
    try:
        configs = {i: experiment_config(i, args.xl) for i in ids}
    except ValueError as e:  # xl for another world (Schelling, Ring World)
        parser.error(str(e))
    if len(ids) == 1 and unsupported_features(configs[ids[0]]):
        try:
            config_to_cfg(configs[ids[0]], steps=1, seed=0)
        except UnsupportedFeature as e:
            parser.error(f"{ids[0]}: {e}")
    skipped = [i for i in ids if unsupported_features(configs[i])]
    out = args.out if args.out is not None else default_out_gpu(args.xl)
    for exp_id in (i for i in ids if i not in skipped):
        paths = run_experiment_gpu(exp_id, args.seeds, args.jobs, out, args.exe, args.xl)
        print(f"{exp_id}: {len(paths)} seeds -> {result_dir(exp_id, out)}", flush=True)
    if skipped:
        print(f"skipped (rules not on the GPU yet): {', '.join(skipped)}")


if __name__ == "__main__":
    main()
