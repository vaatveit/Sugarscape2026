import pytest

from experiments.run import XL_OUT, fingerprint, load_results, main, results_current, run_experiment


def test_xl_run_writes_its_own_results(tmp_path):
    runs = run_experiment("TEST-tiny", seeds=1, out_dir=tmp_path, xl=True)
    assert runs[0][0]["population"] == 2_000 and [r["t"] for r in runs[0]] == list(range(6))
    folder = tmp_path / "TEST-tiny"
    assert (folder / "fingerprint.txt").read_text(encoding="utf-8") == fingerprint("TEST-tiny", xl=True)
    assert not results_current("TEST-tiny", tmp_path, xl=True)  # 1 of the 2 registered seeds
    assert not results_current("TEST-tiny", tmp_path)  # the regular fingerprint doesn't match
    assert load_results("TEST-tiny", out_dir=tmp_path) == runs


def test_xl_fingerprint_names_the_world_and_the_map():
    fp = fingerprint("TEST-tiny", xl=True)
    assert "width=500" in fp and "xl map sha256=" in fp and fp != fingerprint("TEST-tiny")


def test_xl_results_made_before_the_centred_look_are_stale(tmp_path):
    # The look rule is code, not settings, so the fingerprint names it: xl results from an older look must not pass.
    run_experiment("TEST-tiny", out_dir=tmp_path, xl=True)
    assert results_current("TEST-tiny", tmp_path, xl=True)
    fp = tmp_path / "TEST-tiny" / "fingerprint.txt"
    fp.write_text(fp.read_text(encoding="utf-8").replace("look: centred\n", ""), encoding="utf-8")
    assert not results_current("TEST-tiny", tmp_path, xl=True)
    assert "look:" not in fingerprint("TEST-tiny")  # stride 1 looks at every site, whatever the rule


def test_cli_xl_defaults_to_results_xl():
    assert XL_OUT.name == "results-xl"


def test_cli_xl(tmp_path, capsys):
    main(["TEST-tiny", "--xl", "--seeds", "1", "--out", str(tmp_path)])
    assert (tmp_path / "TEST-tiny" / "timing.csv").exists()


@pytest.mark.parametrize("exp_id", ["TEST-schelling", "TEST-ring"])
def test_cli_refuses_xl_for_other_worlds(exp_id):
    with pytest.raises(SystemExit):
        main([exp_id, "--xl"])
