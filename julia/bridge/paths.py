"""Where things are: this repository (code), the Julia project, and the Python results the comparison reads."""

import os
import sys
from pathlib import Path

JULIA_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = JULIA_DIR.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

# The folder holding the Python results/ and results-xl/, written by the user's own sessions (design: Non-goals):
# by default the checkout this julia/ lives in. Read, never written. SUGARSCAPE_RESULTS_ROOT overrides it.
PY_RESULTS = Path(os.environ.get("SUGARSCAPE_RESULTS_ROOT", REPO_ROOT))
