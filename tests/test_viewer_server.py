import http.client
import json
import threading
import urllib.error
import urllib.request
from contextlib import contextmanager

import pytest

from experiments.registry import EXPERIMENTS
from viewer.run import KEEP, LEAD, Run, catalog
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


def start(base, experiment, seed):
    """POST a run; returns its info, whose "run" id later requests must name."""
    status, _, info = call(base, "/api/run", {"experiment": experiment, "seed": seed})
    assert status == 200, info
    return info


def test_connections_are_kept_alive(live):
    # A new connection costs ~300 ms on Windows when "localhost" tries ::1 first; reusing one avoids that.
    _, base = live
    conn = http.client.HTTPConnection(base.removeprefix("http://"))
    for _ in range(2):
        conn.request("GET", "/api/experiments")
        r = conn.getresponse()
        r.read()
        assert r.status == 200 and r.version == 11 and not r.will_close
    conn.close()


def test_binds_loopback_only(live):
    server, _ = live
    assert server.server_address[0] == "127.0.0.1"


def test_experiments_endpoint_is_the_catalog(live):
    _, base = live
    status, headers, body = call(base, "/api/experiments")
    assert status == 200 and body == catalog() and headers["Cache-Control"] == "no-store"


def test_run_then_frames_match_the_run(live):
    _, base = live
    info = start(base, "VI-1", 2)
    assert info["seed"] == EXPERIMENTS["VI-1"].config.seed + 2 and info["tribes"] is True
    assert {k: v for k, v in info.items() if k != "run"} == {k: v for k, v in Run("VI-1", 2).info().items() if k != "run"}
    status, _, frame = call(base, f"/api/frame?run={info['run']}&t=5")
    assert status == 200 and frame["t"] == 5 and frame["latest"] == 5
    assert frame["run"] == info["run"]
    assert {k: v for k, v in frame.items() if k not in ("earliest", "latest", "run")} == Run("VI-1", 2).frame(5).to_json()


def test_population_counts_the_agents_drawn(live):
    _, base = live
    rid = start(base, "VI-1", 0)["run"]
    call(base, f"/api/frame?run={rid}&t=12")
    status, _, pop = call(base, f"/api/population?run={rid}&from=0")
    assert status == 200 and pop["latest"] == 12 and pop["from"] == 0 and len(pop["counts"]) == 13
    for t in range(13):
        assert pop["counts"][t] == len(call(base, f"/api/frame?run={rid}&t={t}")[2]["agents"]["id"])
    assert call(base, f"/api/population?run={rid}&from=10")[2]["counts"] == pop["counts"][10:]


def test_new_run_replaces_the_old(live):
    _, base = live
    old = start(base, "II-4", 0)["run"]
    call(base, f"/api/frame?run={old}&t=10")
    new = start(base, "II-4", 0)["run"]
    assert new != old and call(base, f"/api/frame?run={new}&t=0")[2]["latest"] == 0


def test_requests_for_a_replaced_run_are_409(live):
    # A second tab starting its own run must not feed the first tab another run's frames (final review #1).
    _, base = live
    a = start(base, "VI-1", 0)["run"]
    b = start(base, "II-4", 0)["run"]
    for path in (f"/api/frame?run={a}&t=3", f"/api/population?run={a}&from=0"):
        status, _, err = call(base, path)
        assert status == 409 and "replaced" in err["error"], path
    status, _, frame = call(base, f"/api/frame?run={b}&t=3")
    assert status == 200 and frame["spice"] is None and frame["run"] == b


def test_periods_past_the_window_are_410(live):
    _, base = live
    rid = start(base, "II-4", 0)["run"]
    t = 0
    while t < KEEP + 10:
        t = min(KEEP + 10, t + LEAD)
        assert call(base, f"/api/frame?run={rid}&t={t}")[0] == 200
    status, _, frame = call(base, f"/api/frame?run={rid}&t={t}")
    assert frame["earliest"] == t - KEEP + 1 and frame["latest"] == t
    status, _, err = call(base, f"/api/frame?run={rid}&t=0")
    assert status == 410 and "no longer kept" in err["error"]
    status, _, pop = call(base, f"/api/population?run={rid}&from=0")
    assert len(pop["counts"]) == t + 1 and pop["earliest"] == t - KEEP + 1


def test_bad_requests_are_400(live):
    _, base = live
    for body in ({"experiment": "II-4", "seed": -1}, {"experiment": "II-4", "seed": "x"},
                 {"experiment": "II-4", "seed": 1.5}, {"experiment": "nope", "seed": 0}, {"seed": 0}, [1]):
        status, _, err = call(base, "/api/run", body)
        assert status == 400 and "error" in err, body
    status, _, err = call(base, "/api/run", raw=b"not json")
    assert status == 400 and "error" in err
    rid = start(base, "II-4", 0)["run"]
    for q in (f"run={rid}&t=-1", f"run={rid}&t=abc", f"run={rid}&t={LEAD + 1}", f"run={rid}", "t=0"):
        status, _, err = call(base, f"/api/frame?{q}")
        assert status == 400 and "error" in err, q
    for q in (f"run={rid}&from=-1", f"run={rid}&from=x", "from=0"):
        assert call(base, f"/api/population?{q}")[0] == 400, q


def test_frames_before_any_run_are_409():
    with serving() as (_, base):
        for path in ("/api/frame?run=x&t=0", "/api/population?run=x&from=0"):
            status, _, err = call(base, path)
            assert status == 409 and "error" in err


def test_model_errors_are_500_and_the_server_survives(live):
    server, base = live
    rid = start(base, "II-4", 0)["run"]

    def broken():
        raise RuntimeError("boom")

    real, server.run.model.step = server.run.model.step, broken
    status, _, err = call(base, f"/api/frame?run={rid}&t=1")
    assert status == 500 and "boom" in err["error"]
    assert call(base, "/api/experiments")[0] == 200
    server.run.model.step = real
    status, _, err = call(base, f"/api/frame?run={rid}&t=1")  # the half-stepped model is never stepped again
    assert status == 500 and "boom" in err["error"]
    assert call(base, f"/api/frame?run={rid}&t=0")[0] == 200


def test_unknown_paths_are_404(live):
    _, base = live
    assert call(base, "/api/nope")[0] == 404 and call(base, "/elsewhere")[0] == 404


def test_static_route_cannot_escape_the_folder(live):
    _, base = live
    for path in ("/static/../pyproject.toml", "/static/%2e%2e/pyproject.toml", "/static/..%2fpyproject.toml",
                 "/static/..%5cpyproject.toml", "/static/nope.js", "/static/"):
        assert call(base, path)[0] == 404, path


def test_static_route_serves_exact_file_names_only(live):
    # Windows resolves case variants and ::$DATA streams to the same file; only the real names are served.
    _, base = live
    assert call(base, "/static/style.css")[0] == 200
    for path in ("/static/STYLE.CSS", "/static/Style.css", "/static/style.css::$DATA", "/static/style.css.",
                 "/static/style.css%20", "/static/./style.css"):
        assert call(base, path)[0] == 404, path


def test_modules_are_served_as_javascript(live):
    _, base = live
    status, headers, _ = call(base, "/static/encoding.mjs")
    assert status == 200 and headers["Content-Type"].startswith("text/javascript")
    status, headers, page = call(base, "/")
    assert status == 200 and headers["Content-Type"].startswith("text/html") and "<main" in page
