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


def test_agent_data_read_only_in_diagnostics():
    # Metrics are gathered in bulk between steps and replacement runs on the device (spec 2026-10-25, sections 1-4):
    # no timed host code reads agents through DeviceAgentVector or creates agents; checks.cu is the exception.
    for name in TIMED_HOST_SOURCES:
        assert not POPULATION_READ.search((SRC / name).read_text(encoding="utf-8")), name
    assert "newAgent(" not in (SRC / "host_state.cu").read_text(encoding="utf-8")
