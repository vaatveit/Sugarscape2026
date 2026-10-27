"""GPU seeds against Python's under the Julia agreement rule, with a speed table (spec 2026-10-25-gpu-full-parity,
section 7): <gpu dir>/AGREEMENT.md.

Usage: python -m bridge.agreement_report <id-or-prefix>... [--gpu DIR] [--python DIR] [--out FILE]
The rule (julia/bridge/agreement.py, loaded by path so it has one implementation): each seed's mean of each metric over
each quarter of the run; a Welch t-test per (experiment, metric, quarter) and Fisher's exact test for extinction; all
p-values corrected together by Benjamini-Hochberg at q = 0.01. Ids match as bridge.gpu_run matches them; an experiment
with no seeds on either side is listed as not run.
"""

import argparse
import csv
import importlib.util
import math
from dataclasses import dataclass, field
from pathlib import Path

from bridge.gpu_run import gpu_fingerprint, matching_ids
from bridge.paths import SUGARSCAPE_ROOT
from experiments.registry import EXPERIMENTS
from experiments.run import load_results, result_dir, results_current

_spec = importlib.util.spec_from_file_location("julia_agreement", SUGARSCAPE_ROOT / "julia" / "bridge" / "agreement.py")
agreement = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(agreement)


@dataclass
class Speed:
    experiment: str
    gpu_setup_s: float
    gpu_step_ms: float
    gpu_metrics_ms: float
    py_setup_s: float
    py_step_ms: float
    py_metrics_ms: float

    @property
    def ratio(self) -> float:  # GPU / Python stepping per period
        return self.gpu_step_ms / self.py_step_ms if self.py_step_ms else math.nan


@dataclass
class Report:
    checks: list = field(default_factory=list)
    not_run: list[str] = field(default_factory=list)
    stale: list[str] = field(default_factory=list)
    speed: list[Speed] = field(default_factory=list)

    @property
    def flagged(self) -> list:
        return [c for c in self.checks if c.flagged]

    @property
    def tested(self) -> int:
        return sum(c.kind == "tested" for c in self.checks)


def _has_seeds(exp_id: str, root: Path) -> bool:
    folder = result_dir(exp_id, root)
    return folder.is_dir() and any(folder.glob("seed*.csv"))


def _timing(exp_id: str, root: Path) -> tuple[float, float, float] | None:
    """Mean setup seconds, and stepping and metrics milliseconds per period, over the seeds of timing.csv."""
    path = result_dir(exp_id, root) / "timing.csv"
    if not path.exists():
        return None
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        return None
    mean = lambda key: sum(float(r[key]) for r in rows) / len(rows)  # noqa: E731
    periods = mean("periods")
    if not periods:  # no period stepped: nothing per period to report
        return mean("setup_s"), math.nan, math.nan
    return mean("setup_s"), 1000 * mean("stepping_s") / periods, 1000 * mean("metrics_s") / periods


def build_report(args: list[str], gpu_dir: Path, python_dir: Path) -> Report:
    report = Report()
    ids = list(dict.fromkeys(i for a in args for i in matching_ids(a, EXPERIMENTS)))
    for exp_id in ids:
        if not (_has_seeds(exp_id, gpu_dir) and _has_seeds(exp_id, python_dir)):
            report.not_run.append(exp_id)
            continue
        report.checks += agreement.compare_experiment(exp_id, load_results(exp_id, python_dir),
                                                      load_results(exp_id, gpu_dir))
        fp = result_dir(exp_id, gpu_dir) / "fingerprint.txt"
        if not results_current(exp_id, python_dir) or not fp.exists() or fp.read_text(encoding="utf-8") != gpu_fingerprint(exp_id):
            report.stale.append(exp_id)
        g, p = _timing(exp_id, gpu_dir), _timing(exp_id, python_dir)
        if g and p:
            report.speed.append(Speed(exp_id, *g, *p))
    agreement.flag(report.checks)
    return report


def _num(v: float, digits: int = 4) -> str:
    return "nan" if v is None or (isinstance(v, float) and math.isnan(v)) else f"{v:.{digits}g}"


def _label(c) -> str:
    return f"{c.experiment} {c.metric or 'extinction'}" + ("" if c.window is None else f" quarter {c.window + 1}")


def write_report(report: Report, path: Path) -> None:
    checks = report.checks
    lines = ["# GPU against Python: agreement", "",
             f"{report.tested} tested windows, {len(report.flagged)} flagged (Benjamini-Hochberg, q = 0.01); "
             f"{sum(c.kind == 'untestable' for c in checks)} untestable; {len(report.not_run)} experiments not run.", ""]
    lines += ["## Flagged", ""]
    lines += [f"- {_label(c)}: p {c.p:.2g}, Python {_num(c.mean_py)}, GPU {_num(c.mean_jl)} "
              f"({_num(c.diff_sd, 3)} Python seed SDs)" for c in report.flagged] or ["None."]
    near = sorted((c for c in checks if not c.flagged and c.kind in ("tested", "extinction") and c.p < 0.01),
                  key=lambda c: c.p)
    lines += ["", "## Unflagged with p < 0.01", ""]
    lines += [f"- {_label(c)}: p {c.p:.2g}, Python {_num(c.mean_py)}, GPU {_num(c.mean_jl)}" for c in near] or ["None."]
    lines += ["", "## Untestable windows (fewer than two seed values on a side)", ""]
    lines += [f"- {_label(c)}" for c in checks if c.kind == "untestable"] or ["None."]
    lines += ["", "## Not run", ""] + ([f"- {i}" for i in report.not_run] or ["None."])
    lines += ["", "## Stale fingerprints", ""] + ([f"- {i}" for i in report.stale] or ["None."])
    lines += ["", "## Speed (per period; development timings, uncontrolled)", "",
              "| Experiment | GPU setup s | GPU step ms | GPU metrics ms | Python setup s | Python step ms | "
              "Python metrics ms | GPU / Python step |", "|---|---|---|---|---|---|---|---|"]
    lines += [f"| {s.experiment} | {_num(s.gpu_setup_s)} | {_num(s.gpu_step_ms)} | {_num(s.gpu_metrics_ms)} | "
              f"{_num(s.py_setup_s)} | {_num(s.py_step_ms)} | {_num(s.py_metrics_ms)} | {_num(s.ratio, 3)} |"
              for s in report.speed]
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("ids", nargs="+")
    parser.add_argument("--gpu", type=Path, default=Path("results-gpu"))
    parser.add_argument("--python", type=Path, default=SUGARSCAPE_ROOT / "results")
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args(argv)
    report = build_report(args.ids, args.gpu, args.python)
    out = args.out or args.gpu / "AGREEMENT.md"
    write_report(report, out)
    print(f"wrote {out}: {report.tested} tested windows, {len(report.flagged)} flagged, {len(report.not_run)} not run")


if __name__ == "__main__":
    main()
