"""GPU seeds against Python's (or Julia's) under the Julia agreement rule, with a speed table (spec
2026-10-25-gpu-full-parity, section 7): <gpu dir>/AGREEMENT.md.

Usage: python -m bridge.agreement_report <id-or-prefix>... [--xl] [--gpu DIR] [--python DIR] [--reference julia]
       [--julia DIR] [--timing DIR] [--out FILE]
--xl compares the xl versions; --reference julia scores against Julia's results in --julia (where Python has none);
--julia alone adds Julia's stepping to the speed table; --timing reads the GPU's timings from another folder (the
fast build's, run one job at a time).
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

from bridge.gpu_run import gpu_current, matching_ids
from bridge.paths import SUGARSCAPE_ROOT
from experiments.registry import EXPERIMENTS
from experiments.run import fingerprint, load_results, result_dir, results_current

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
    julia_step_ms: float = math.nan  # with --julia (plan 2026-10-27-gpu-parity-part-f)

    @property
    def ratio(self) -> float:  # GPU / Python stepping per period
        return self.gpu_step_ms / self.py_step_ms if self.py_step_ms else math.nan

    @property
    def julia_ratio(self) -> float:  # GPU / Julia stepping per period
        return self.gpu_step_ms / self.julia_step_ms if self.julia_step_ms else math.nan


@dataclass
class Report:
    reference: str = "Python"  # the side the GPU is scored against: "Python" or "Julia"
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


def _fingerprint_is(folder: Path, text: str) -> bool:
    fp = folder / "fingerprint.txt"
    return fp.exists() and fp.read_text(encoding="utf-8") == text


def _reference_current(exp_id: str, ref_dir: Path, reference: str, xl: bool) -> bool:
    """Python's results as experiments.run checks them; Julia's carry Python's fingerprint after a "julia" line, and
    like Python's hold every registered seed."""
    if reference == "julia":
        folder = result_dir(exp_id, ref_dir)
        return (_fingerprint_is(folder, "julia\n" + fingerprint(exp_id, xl))
                and all((folder / f"seed{k}.csv").exists() for k in range(EXPERIMENTS[exp_id].seeds)))
    return results_current(exp_id, ref_dir, xl=xl)


def build_report(args: list[str], gpu_dir: Path, ref_dir: Path, *, xl: bool = False, reference: str = "python",
                 julia_dir: Path | None = None, timing_dir: Path | None = None) -> Report:
    """The GPU's seeds in gpu_dir against the reference's (Python's or Julia's) in ref_dir, for the regular or xl
    versions. The speed rows read the GPU's timing.csv from timing_dir (default gpu_dir), the reference's from ref_dir,
    and with julia_dir Julia's too."""
    report = Report(reference="Julia" if reference == "julia" else "Python")
    timing_dir = gpu_dir if timing_dir is None else timing_dir
    ids = list(dict.fromkeys(i for a in args for i in matching_ids(a, EXPERIMENTS)))
    for exp_id in ids:
        if not (_has_seeds(exp_id, gpu_dir) and _has_seeds(exp_id, ref_dir)):
            report.not_run.append(exp_id)
            continue
        report.checks += agreement.compare_experiment(exp_id, load_results(exp_id, ref_dir),
                                                      load_results(exp_id, gpu_dir))
        if not (_reference_current(exp_id, ref_dir, reference, xl) and gpu_current(exp_id, gpu_dir, xl)):
            report.stale.append(exp_id)
        g, p = _timing(exp_id, timing_dir), _timing(exp_id, ref_dir)
        if g and p:
            j = _timing(exp_id, julia_dir) if julia_dir is not None else None
            report.speed.append(Speed(exp_id, *g, *p, julia_step_ms=j[1] if j else math.nan))
    agreement.flag(report.checks)
    return report


def _num(v: float, digits: int = 4) -> str:
    return "nan" if v is None or (isinstance(v, float) and math.isnan(v)) else f"{v:.{digits}g}"


def _label(c) -> str:
    return f"{c.experiment} {c.metric or 'extinction'}" + ("" if c.window is None else f" quarter {c.window + 1}")


def write_report(report: Report, path: Path) -> None:
    checks = report.checks
    ref = report.reference
    lines = [f"# GPU against {ref}: agreement", "",
             f"{report.tested} tested windows, {len(report.flagged)} flagged (Benjamini-Hochberg, q = 0.01); "
             f"{sum(c.kind == 'untestable' for c in checks)} untestable; {len(report.not_run)} experiments not run.", ""]
    lines += ["## Flagged", ""]
    lines += [f"- {_label(c)}: p {c.p:.2g}, {ref} {_num(c.mean_py)}, GPU {_num(c.mean_jl)} "
              f"({_num(c.diff_sd, 3)} {ref} seed SDs)" for c in report.flagged] or ["None."]
    near = sorted((c for c in checks if not c.flagged and c.kind in ("tested", "extinction") and c.p < 0.01),
                  key=lambda c: c.p)
    lines += ["", "## Unflagged with p < 0.01", ""]
    lines += [f"- {_label(c)}: p {c.p:.2g}, {ref} {_num(c.mean_py)}, GPU {_num(c.mean_jl)}" for c in near] or ["None."]
    lines += ["", "## Untestable windows (fewer than two seed values on a side)", ""]
    lines += [f"- {_label(c)}" for c in checks if c.kind == "untestable"] or ["None."]
    lines += ["", "## Not run", ""] + ([f"- {i}" for i in report.not_run] or ["None."])
    lines += ["", "## Stale fingerprints or missing seeds", ""] + ([f"- {i}" for i in report.stale] or ["None."])
    lines += ["", "## Speed (per period; development timings, uncontrolled)", "",
              f"| Experiment | GPU setup s | GPU step ms | GPU metrics ms | {ref} setup s | {ref} step ms | "
              f"{ref} metrics ms | GPU / {ref} step | Julia step ms | GPU / Julia step |",
              "|---|---|---|---|---|---|---|---|---|---|"]
    lines += [f"| {s.experiment} | {_num(s.gpu_setup_s)} | {_num(s.gpu_step_ms)} | {_num(s.gpu_metrics_ms)} | "
              f"{_num(s.py_setup_s)} | {_num(s.py_step_ms)} | {_num(s.py_metrics_ms)} | {_num(s.ratio, 3)} | "
              f"{_num(s.julia_step_ms)} | {_num(s.julia_ratio, 3)} |" for s in report.speed]
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("ids", nargs="+")
    parser.add_argument("--xl", action="store_true", help="the xl versions (default folders results-gpu-xl, results-xl)")
    parser.add_argument("--gpu", type=Path, default=None, help="default: results-gpu, or results-gpu-xl with --xl")
    parser.add_argument("--python", type=Path, default=None, help="default: <root>/results, or results-xl with --xl")
    parser.add_argument("--reference", choices=("python", "julia"), default="python",
                        help="score against Julia's results in --julia instead of Python's")
    parser.add_argument("--julia", type=Path, default=None, help="Julia's results: the reference, or timings only")
    parser.add_argument("--timing", type=Path, default=None, help="where the GPU's timing.csv is read (default --gpu)")
    parser.add_argument("--out", type=Path, default=None)
    args = parser.parse_args(argv)
    gpu = args.gpu or Path("results-gpu-xl" if args.xl else "results-gpu")
    if args.reference == "julia":
        if args.julia is None:
            parser.error("--reference julia needs --julia DIR")
        ref = args.julia
    else:
        ref = args.python or SUGARSCAPE_ROOT / ("results-xl" if args.xl else "results")
    report = build_report(args.ids, gpu, ref, xl=args.xl, reference=args.reference, julia_dir=args.julia,
                          timing_dir=args.timing)
    out = args.out or gpu / "AGREEMENT.md"
    write_report(report, out)
    print(f"wrote {out}: {report.tested} tested windows, {len(report.flagged)} flagged, {len(report.not_run)} not run")


if __name__ == "__main__":
    main()
