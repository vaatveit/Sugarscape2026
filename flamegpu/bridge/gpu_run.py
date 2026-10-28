"""Run registered experiments on the GPU: one seed{k}.csv per seed, as the Python project's experiments.run writes.

Usage: python -m bridge.gpu_run <id-or-prefix>... [--seeds N] [--jobs J] [--out DIR] [--xl] [--exe PATH] [--resume]
A prefix such as "II" runs every "II-..." id; "II-5" runs every "II-5/..." id. --xl runs the 500x500 version
(docs/xl.md) into results-gpu-xl/. Each run also writes timing.csv and machine.txt. --resume keeps every experiment
whose results are already current and complete, so a stopped run picks up where it left off. The Schelling and Ring
World models are skipped by the user's decision (plan 2026-10-27-gpu-parity-part-f).
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
from sugarscape.config import Config

# 2026-10-25: movement and neighbour counts in Python's order (phase2); Python's 45 metric columns and the Chapter
# III rules (phase3, spec 2026-10-25-gpu-full-parity); every Config rule (parity, Part F's rerun of everything), so
# every result made before is stale.
GPU_FINGERPRINT = "gpu-parity\n"
# Replacement moved to the device (spec 2026-10-25): its random stream changed, so results made before are stale.
REPLACEMENT_FINGERPRINT = "replacement: device\n"


def gpu_fingerprint(exp_id: str, xl: bool = False) -> str:
    """The fingerprint.txt of the GPU's results for an experiment (or its xl version).

    xl's looks follow Python's centred look (docs/xl.md), which Python's xl fingerprint names in its first line.
    """
    extra = REPLACEMENT_FINGERPRINT if experiment_config(exp_id, xl).replacement else ""
    return GPU_FINGERPRINT + extra + fingerprint(exp_id, xl)


def gpu_current(exp_id: str, gpu_dir: Path, xl: bool = False, seeds: int | None = None) -> bool:
    """GPU results match the experiment's current settings and hold every seed (the registered count, or `seeds`), as
    the Python project's results_current."""
    folder = result_dir(exp_id, gpu_dir)
    fp = folder / "fingerprint.txt"
    if not fp.exists() or fp.read_text(encoding="utf-8") != gpu_fingerprint(exp_id, xl):
        return False
    n = EXPERIMENTS[exp_id].seeds if seeds is None else seeds
    return all((folder / f"seed{k}.csv").exists() for k in range(n))


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
    for old in [*folder.glob("seed*.csv"), folder / "fingerprint.txt"]:  # a stopped run leaves no current fingerprint
        old.unlink(missing_ok=True)
    texts = [config_to_cfg(config, steps=exp.steps, seed=config.seed + k) for k in range(n)]
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        timings = list(pool.map(lambda k: _run_seed(Path(exe), folder, texts[k], k), range(n)))
    (folder / "fingerprint.txt").write_text(gpu_fingerprint(exp_id, xl), encoding="utf-8")
    write_timing_csv(folder / "timing.csv", [timing_row(k, t) for k, t in enumerate(timings)])
    (folder / "machine.txt").write_text(machine_note(Path(exe), jobs), encoding="utf-8")
    return [folder / f"seed{k}.csv" for k in range(n)]


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("ids", nargs="+")
    parser.add_argument("--seeds", type=int, default=None)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--out", type=Path, default=None, help="default: results-gpu/, or results-gpu-xl/ with --xl")
    parser.add_argument("--xl", action="store_true", help="run the 500x500 xl version (docs/xl.md)")
    parser.add_argument("--exe", type=Path, default=EXE, help="the program (default: the seatbelts-on build)")
    parser.add_argument("--resume", action="store_true", help="keep experiments whose results are current and complete")
    args = parser.parse_args(argv)
    for arg in args.ids:
        if not matching_ids(arg, EXPERIMENTS):
            parser.error(f"no experiment matches {arg!r}")
    ids = list(dict.fromkeys(i for a in args.ids for i in matching_ids(a, EXPERIMENTS)))
    # The Schelling and Ring World models: skipped by decision. One named on its own is still an error, as before.
    by_decision = [i for i in ids if not isinstance(EXPERIMENTS[i].config, Config) and i not in args.ids]
    ids = [i for i in ids if i not in by_decision]
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
        if args.resume and gpu_current(exp_id, out, args.xl, args.seeds):
            print(f"{exp_id}: current, kept", flush=True)
            continue
        paths = run_experiment_gpu(exp_id, args.seeds, args.jobs, out, args.exe, args.xl)
        print(f"{exp_id}: {len(paths)} seeds -> {result_dir(exp_id, out)}", flush=True)
    if skipped:
        print(f"skipped (rules not on the GPU yet): {', '.join(skipped)}")
    if by_decision:
        print(f"skipped by decision (Schelling and Ring World, plan 2026-10-27-gpu-parity-part-f): "
              f"{', '.join(by_decision)}")


if __name__ == "__main__":
    main()
