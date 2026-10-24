import hashlib
from importlib import resources
from pathlib import Path

DOC = Path(__file__).parent.parent / "docs" / "xl.md"


def test_spec_names_the_committed_map_checksum():
    data = resources.files("sugarscape.maps").joinpath("sugar-map-xl.txt").read_bytes()
    assert hashlib.sha256(data).hexdigest() in DOC.read_text(encoding="utf-8")
