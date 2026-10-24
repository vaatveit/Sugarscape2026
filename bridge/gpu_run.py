"""Run registered experiments on the GPU: one seed{k}.csv per seed, as the Python project's experiments.run writes.

Usage: python -m bridge.gpu_run <id-or-prefix> [--seeds N] [--jobs J] [--out DIR]
A prefix such as "II" runs every "II-..." id; "II-5" runs every "II-5/..." id.
"""

import argparse
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from bridge.paths import EXE, subprocess_env
from bridge.config_cfg import UnsupportedFeature, config_to_cfg, unsupported_features
from experiments.registry import EXPERIMENTS
from experiments.run import fingerprint, result_dir

GPU_FINGERPRINT = "gpu-phase1\n"


def matching_ids(arg: str, ids) -> list[str]:
    """The id itself, else its sweep points ("II-5" -> "II-5/..."), else a chapter ("II" -> "II-...")."""
    ids = list(ids)
    if arg in ids:
        return [arg]
    sweep = [i for i in ids if i.startswith(arg + "/")]
    return sweep or [i for i in ids if i.startswith(arg + "-")]


def _run_seed(exe: Path, folder: Path, cfg_text: str, k: int) -> Path:
    cfg = folder / f"run{k}.cfg"
    cfg.write_text(cfg_text, encoding="utf-8")
    out = folder / f"seed{k}.csv"
    result = subprocess.run([str(exe), "--config", str(cfg), "--out", str(out)], capture_output=True, text=True,
                            env=subprocess_env())
    if result.returncode != 0:
        raise RuntimeError(f"{folder.name} seed {k}: exit {result.returncode}: {result.stderr.strip()}")
    return out


def run_experiment_gpu(exp_id: str, seeds: int | None = None, jobs: int = 1, out_dir: Path = Path("results-gpu"),
                       exe: Path = EXE) -> list[Path]:
    """Run seeds base + 0 .. base + n-1 of one experiment; returns the seed CSV paths."""
    exp = EXPERIMENTS[exp_id]
    n = seeds if seeds is not None else exp.seeds
    folder = result_dir(exp_id, Path(out_dir))
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("seed*.csv"):
        old.unlink()
    texts = [config_to_cfg(exp.config, steps=exp.steps, seed=exp.config.seed + k) for k in range(n)]
    with ThreadPoolExecutor(max_workers=max(1, jobs)) as pool:
        paths = list(pool.map(lambda k: _run_seed(Path(exe), folder, texts[k], k), range(n)))
    (folder / "fingerprint.txt").write_text(GPU_FINGERPRINT + fingerprint(exp_id), encoding="utf-8")
    return paths


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("id")
    parser.add_argument("--seeds", type=int, default=None)
    parser.add_argument("--jobs", type=int, default=1)
    parser.add_argument("--out", type=Path, default=Path("results-gpu"))
    args = parser.parse_args(argv)
    ids = matching_ids(args.id, EXPERIMENTS)
    if not ids:
        parser.error(f"no experiment matches {args.id!r}")
    if len(ids) == 1 and unsupported_features(EXPERIMENTS[ids[0]].config):
        try:
            config_to_cfg(EXPERIMENTS[ids[0]].config, steps=1, seed=0)
        except UnsupportedFeature as e:
            parser.error(f"{ids[0]}: {e}")
    skipped = [i for i in ids if unsupported_features(EXPERIMENTS[i].config)]
    for exp_id in (i for i in ids if i not in skipped):
        paths = run_experiment_gpu(exp_id, args.seeds, args.jobs, args.out)
        print(f"{exp_id}: {len(paths)} seeds -> {result_dir(exp_id, args.out)}", flush=True)
    if skipped:
        print(f"skipped (rules not on the GPU yet): {', '.join(skipped)}")


if __name__ == "__main__":
    main()
