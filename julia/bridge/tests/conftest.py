import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

import bridge.paths  # noqa: E402,F401  (puts the repository root on sys.path)
