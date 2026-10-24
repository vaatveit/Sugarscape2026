import json
import threading
import urllib.error
import urllib.request
from contextlib import contextmanager

import pytest

from experiments.registry import EXPERIMENTS
from viewer.run import LEAD, Run, catalog
from viewer.server import make_server


@contextmanager
def serving():
    server = make_server(0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server, "http://127.0.0.1:%d" % server.server_address[1]
    finally:
        server.shutdown()
        server.server_close()


@pytest.fixture(scope="module")
def live():
    with serving() as pair:
        yield pair


def call(base, path, body=None, raw=None):
    """(status, headers, decoded body): JSON bodies are parsed, others returned as text."""
    data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
    req = urllib.request.Request(base + path, data=data, method="POST" if data is not None else "GET")
    try:
        with urllib.request.urlopen(req) as r:
            status, headers, payload = r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        status, headers, payload = e.code, e.headers, e.read()
    text = payload.decode()
    return status, headers, json.loads(text) if headers.get("Content-Type", "").startswith("application/json") else text


def test_binds_loopback_only(live):
    server, _ = live
    assert server.server_address[0] == "127.0.0.1"


def test_experiments_endpoint_is_the_catalog(live):
    _, base = live
    status, headers, body = call(base, "/api/experiments")
    assert status == 200 and body == catalog() and headers["Cache-Control"] == "no-store"


def test_run_then_frames_match_the_run(live):
    _, base = live
    status, _, info = call(base, "/api/run", {"experiment": "VI-1", "seed": 2})
    assert status == 200 and info["seed"] == EXPERIMENTS["VI-1"].config.seed + 2 and info["tribes"] is True
    assert info == Run("VI-1", 2).info()
    status, _, frame = call(base, "/api/frame?t=5")
    assert status == 200 and frame["t"] == 5 and frame["latest"] == 5
    assert {k: v for k, v in frame.items() if k != "latest"} == Run("VI-1", 2).frame(5).to_json()


def test_population_counts_the_agents_drawn(live):
    _, base = live
    call(base, "/api/run", {"experiment": "VI-1", "seed": 0})
    call(base, "/api/frame?t=12")
    status, _, pop = call(base, "/api/population?from=0")
    assert status == 200 and pop["latest"] == 12 and pop["from"] == 0 and len(pop["counts"]) == 13
    for t in range(13):
        assert pop["counts"][t] == len(call(base, f"/api/frame?t={t}")[2]["agents"]["id"])
    assert call(base, "/api/population?from=10")[2]["counts"] == pop["counts"][10:]


def test_new_run_replaces_the_old(live):
    _, base = live
    call(base, "/api/run", {"experiment": "II-4", "seed": 0})
    call(base, "/api/frame?t=10")
    call(base, "/api/run", {"experiment": "II-4", "seed": 0})
    assert call(base, "/api/frame?t=0")[2]["latest"] == 0


def test_bad_requests_are_400(live):
    _, base = live
    for body in ({"experiment": "II-4", "seed": -1}, {"experiment": "II-4", "seed": "x"},
                 {"experiment": "II-4", "seed": 1.5}, {"experiment": "nope", "seed": 0}, {"seed": 0}, [1]):
        status, _, err = call(base, "/api/run", body)
        assert status == 400 and "error" in err, body
    status, _, err = call(base, "/api/run", raw=b"not json")
    assert status == 400 and "error" in err
    call(base, "/api/run", {"experiment": "II-4", "seed": 0})
    for q in ("t=-1", "t=abc", f"t={LEAD + 1}", ""):
        status, _, err = call(base, f"/api/frame?{q}")
        assert status == 400 and "error" in err, q
    for q in ("from=-1", "from=x"):
        assert call(base, f"/api/population?{q}")[0] == 400, q


def test_frames_before_any_run_are_409():
    with serving() as (_, base):
        for path in ("/api/frame?t=0", "/api/population?from=0"):
            status, _, err = call(base, path)
            assert status == 409 and "error" in err


def test_model_errors_are_500_and_the_server_survives(live):
    server, base = live
    call(base, "/api/run", {"experiment": "II-4", "seed": 0})

    def broken():
        raise RuntimeError("boom")

    server.run.model.step = broken
    status, _, err = call(base, "/api/frame?t=1")
    assert status == 500 and "boom" in err["error"]
    assert call(base, "/api/experiments")[0] == 200


def test_unknown_paths_are_404(live):
    _, base = live
    assert call(base, "/api/nope")[0] == 404 and call(base, "/elsewhere")[0] == 404


def test_static_route_cannot_escape_the_folder(live):
    _, base = live
    for path in ("/static/../pyproject.toml", "/static/%2e%2e/pyproject.toml", "/static/..%2fpyproject.toml",
                 "/static/..%5cpyproject.toml", "/static/nope.js", "/static/"):
        assert call(base, path)[0] == 404, path


def test_modules_are_served_as_javascript(live):
    _, base = live
    status, headers, _ = call(base, "/static/encoding.mjs")
    assert status == 200 and headers["Content-Type"].startswith("text/javascript")
    status, headers, page = call(base, "/")
    assert status == 200 and headers["Content-Type"].startswith("text/html") and "<main" in page
