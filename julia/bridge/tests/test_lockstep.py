from bridge.lockstep import CASES, FIXTURES, fixture_text
from bridge.paths import JULIA_DIR


def test_lockstep_fixtures_are_current():
    assert FIXTURES == JULIA_DIR / "test" / "fixtures" / "lockstep.toml"
    assert FIXTURES.read_text(encoding="utf-8") == fixture_text()


def test_cases_cover_movement_combat_seasons_and_pollution():
    assert {"II-4", "II-7", "II-8", "III-9", "III-13"} <= set(CASES)
