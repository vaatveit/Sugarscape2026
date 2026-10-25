"""Source checks for rules a run's output cannot show."""

import re
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src"

# Host code that runs in setup or in a period. checks.cu (dumps, --check) is the diagnostics exception, and the .cuh
# files are device code.
TIMED_HOST_SOURCES = ("host_state.cu", "main.cu", "metrics.cu", "model.cu")
SITE_SIZED_ACCESS = re.compile(r"getMacroProperty<[^>]*MAX_CELLS")


def test_no_site_sized_host_macro_access():
    # A host access copies the whole macro property, sized for SUGARSCAPE_MAX_CELLS whatever the world (spec 3).
    offending = [f"{name}:{n}: {line.strip()}"
                 for name in TIMED_HOST_SOURCES
                 for n, line in enumerate((SRC / name).read_text(encoding="utf-8").splitlines(), 1)
                 if SITE_SIZED_ACCESS.search(line)]
    assert offending == [], "host code touches a site-sized macro property:\n" + "\n".join(offending)


POPULATION_READ = re.compile(r"\.getPopulationData\(\)")  # HostAgentAPI's per-agent DeviceAgentVector


def _between(text, start, end_pattern):
    i = text.index(start)
    m = re.compile(end_pattern).search(text, i + len(start))
    return text[i:m.start() if m else len(text)]


def test_metrics_not_read_per_agent():
    # Metrics are gathered in bulk between steps (spec 2026-10-25, section 4); only replace_dead may still read
    # agents through DeviceAgentVector in timed host code (until Task 2), and the diagnostics in checks.cu.
    text = (SRC / "host_state.cu").read_text(encoding="utf-8")
    outside = text.replace(_between(text, "FLAMEGPU_HOST_FUNCTION(replace_dead)", r"\nFLAMEGPU_|\Z"), "")
    assert not POPULATION_READ.search(outside)
    for name in ("main.cu", "metrics.cu", "model.cu"):
        assert not POPULATION_READ.search((SRC / name).read_text(encoding="utf-8")), name
