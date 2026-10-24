"""Write the golden files for test_golden.py with the program bridge.paths.EXE names.

Usage (from flamegpu/): .venv\\Scripts\\python tests\\make_golden.py
Run once, before a change the golden runs must survive; never to make a failing test pass.
"""

import tempfile
from pathlib import Path

from test_golden import GOLDEN, GOLDEN_CASES, run_case  # first: conftest puts flamegpu/ on sys.path

from bridge.paths import EXE


def main() -> None:
    for name in GOLDEN_CASES:
        with tempfile.TemporaryDirectory() as tmp:
            files = run_case(EXE, Path(tmp), name)
        folder = GOLDEN / name
        folder.mkdir(parents=True, exist_ok=True)
        for f, data in files.items():
            (folder / f).write_bytes(data)
        print(f"{name}: {', '.join(f'{f} {len(d)} bytes' for f, d in files.items())}")


if __name__ == "__main__":
    main()
