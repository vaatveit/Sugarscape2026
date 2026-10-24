from bridge.paths import JULIA_DIR
from bridge.scenarios import FIXTURES, SCENARIOS, fixture_text, run_scenario, same_state


def test_fixtures_are_current():
    assert FIXTURES == JULIA_DIR / "test" / "fixtures" / "scenarios.toml"
    assert FIXTURES.read_text(encoding="utf-8") == fixture_text()


def test_every_scenario_is_order_free():
    for name, sc in SCENARIOS.items():
        first = run_scenario(sc, 0)
        for seed in (1, 2):
            assert same_state(run_scenario(sc, seed), first), name


def test_chapter_two_scenarios_are_there():
    assert {"g1_move", "g_inf", "wrap_max_vision", "starvation", "max_age_death", "seasons_fractional",
            "seasons_pulse", "pollution", "pollution_diffusion", "pollution_diffusion_3_passes"} <= set(SCENARIOS)
