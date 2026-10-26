"""Chapter III state at setup (spec 2026-10-25-gpu-full-parity, Part A, Task 2): tribal blocks, sex and fertility
ages, cultural tags, uids, and the new --init and dump columns."""

from gpu import SUGAR_MAP, run_gpu

TAGS = 11
III_12 = {"tag_length": str(TAGS), "vision": "1,10", "endowment": "25,50",
          "initial_blocks": "blue,0,0,20,20,370;red,30,30,20,20,370"}
III_1 = {"sex": "true", "max_age": "60,100", "endowment": "50,100"}


def _tribe(tags: str) -> str:
    return "blue" if 2 * tags.count("1") < len(tags) else "red"


def _run(exe, tmp_path, cfg, steps=1, dump_at=0, agents=None):
    dump = run_gpu(exe, tmp_path, {"map": str(SUGAR_MAP), **cfg}, agents=agents, steps=steps, dump_at=dump_at)
    assert dump.returncode == 0, dump.stderr
    return dump.agents


def test_tribal_blocks_founders(exe, tmp_path):
    agents = _run(exe, tmp_path, III_12)
    assert len(agents) == 740
    blue = [a for a in agents if _tribe(a["tags"]) == "blue"]
    red = [a for a in agents if _tribe(a["tags"]) == "red"]
    assert len(blue) == 370 and len(red) == 370
    assert all(0 <= a["x"] < 20 and 0 <= a["y"] < 20 for a in blue)
    assert all(30 <= a["x"] < 50 and 30 <= a["y"] < 50 for a in red)
    assert all(len(a["tags"]) == TAGS for a in agents)
    assert sorted(a["uid"] for a in agents) == list(range(740))


def test_sex_and_fertility_ranges(exe, tmp_path):
    agents = _run(exe, tmp_path, III_1)
    assert len(agents) == 400
    females = [a for a in agents if a["sex"] == "F"]
    males = [a for a in agents if a["sex"] == "M"]
    assert len(females) + len(males) == 400
    assert 160 <= len(females) <= 240
    assert all(12 <= a["fertility_start"] <= 15 for a in agents)
    assert all(40 <= a["fertility_end"] <= 50 for a in females)
    assert all(50 <= a["fertility_end"] <= 60 for a in males)
    assert all(a["initial_sugar"] == a["sugar"] for a in agents)
    assert all(a["tags"] == "" for a in agents)


def test_init_columns_round_trip(exe, tmp_path):
    given = [
        {"x": 2, "y": 2, "vision": 1, "metabolism": 1, "sugar": 10.0, "age": 3, "max_age": 90, "sex": "F",
         "fertility_start": 12, "fertility_end": 45, "initial_sugar": 8.0, "tags": "10110"},
        {"x": 12, "y": 2, "vision": 2, "metabolism": 2, "sugar": 11.0, "age": 4, "max_age": 80, "sex": "M",
         "fertility_start": 13, "fertility_end": 55, "initial_sugar": 9.0, "tags": "00001"},
        {"x": 2, "y": 12, "vision": 3, "metabolism": 3, "sugar": 12.0, "age": 5, "max_age": 70, "sex": "F",
         "fertility_start": 14, "fertility_end": 41, "initial_sugar": 12.0, "tags": "11111"},
        {"x": 12, "y": 12, "vision": 3, "metabolism": 4, "sugar": 13.0, "age": 6, "max_age": 60, "sex": "M",
         "fertility_start": 15, "fertility_end": 52, "initial_sugar": 7.5, "tags": "00000"},
    ]
    agents = _run(exe, tmp_path, {"sex": "true", "tag_length": "5", "max_age": "60,100"}, agents=given)
    by_site = {(a["x"], a["y"]): a for a in agents}
    for g in given:
        a = by_site[(g["x"], g["y"])]
        for key, value in g.items():
            assert a[key] == value, (key, a[key], value)


def test_newcomer_has_tags_and_sex(exe, tmp_path):
    agents = _run(exe, tmp_path, {"tag_length": str(TAGS), "sex": "true", "replacement": "true", "max_age": "1,1"},
                  steps=1, dump_at=1)
    assert len(agents) == 400
    assert all(a["sex"] in ("F", "M") for a in agents)
    assert all(len(a["tags"]) == TAGS and set(a["tags"]) <= {"0", "1"} for a in agents)
    assert len({a["uid"] for a in agents}) == 400 and min(a["uid"] for a in agents) >= 400
