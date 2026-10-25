"""Every registered experiment's fingerprint, against values recorded before the xl work changed Config and the runner
(docs/superpowers/specs/2026-10-24-xl-design.md, "No regular change").

A fingerprint names the settings saved results came from, so a change here makes those results stale. After an
intended registry change, re-record with: .venv/Scripts/python tests/test_fingerprints.py
"""

import hashlib
from pathlib import Path

from experiments.registry import EXPERIMENTS
from experiments.run import fingerprint

RECORD = Path(__file__).with_name("regular-fingerprints.txt")  # experiment id, SHA-256 of its fingerprint


def current() -> dict[str, str]:
    return {i: hashlib.sha256(fingerprint(i).encode()).hexdigest() for i in sorted(EXPERIMENTS)}


def test_regular_fingerprints_match_the_record():
    recorded = dict(line.split(" ") for line in RECORD.read_text(encoding="utf-8").splitlines())
    now = current()
    changed = sorted(i for i in recorded.keys() | now.keys() if recorded.get(i) != now.get(i))
    assert not changed, f"fingerprints differ from {RECORD.name} for {changed}"


if __name__ == "__main__":
    RECORD.write_text("".join(f"{i} {h}\n" for i, h in current().items()), encoding="utf-8", newline="\n")
