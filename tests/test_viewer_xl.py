import json
import threading
import urllib.error
import urllib.request
from contextlib import contextmanager

import pytest

from viewer.run import KEEP, KEEP_XL, Run
from viewer.server import make_server


# serving() and call() as in test_viewer_server.py (tests/ is not a package, so they can't be imported).
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


def call(base, path, body=None):
    """(status, headers, decoded body): JSON bodies are parsed, others returned as text."""
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, method="POST" if data is not None else "GET")
    try:
        with urllib.request.urlopen(req) as r:
            status, headers, payload = r.status, r.headers, r.read()
    except urllib.error.HTTPError as e:
        status, headers, payload = e.code, e.headers, e.read()
    text = payload.decode()
    return status, headers, json.loads(text) if headers.get("Content-Type", "").startswith("application/json") else text


@pytest.fixture(scope="module")
def live_server():
    with serving() as (_, base):
        yield base


@pytest.fixture(scope="module")
def xl_run():
    return Run("II-4", 0, xl=True)  # 40,000 founders; built once, never stepped


def test_xl_run_reports_its_world(xl_run):
    info = xl_run.info()
    assert info["xl"] is True and info["keep"] == KEEP_XL == 100
    assert (info["width"], info["height"]) == (500, 500)
    assert len(info["sugar_capacity"]) == 250_000
    cap = xl_run.model.landscape.capacity
    assert info["sugar_capacity"][123 * 500 + 456] == cap[123, 456]  # x * height + y


def test_xl_run_keeps_100_periods(xl_run):
    assert xl_run._frames.maxlen == KEEP_XL


def test_xl_first_frame_is_the_whole_world(xl_run):
    frame = xl_run.frame(0)
    assert len(frame.sugar) == 250_000 and frame.population == 40_000


def test_regular_runs_are_unchanged():
    info = Run("II-4", 0).info()
    assert info["xl"] is False and info["keep"] == KEEP == 500


def test_post_xl(live_server):
    base = live_server
    status, _, info = call(base, "/api/run", {"experiment": "II-4", "seed": 0, "xl": True})
    assert status == 200 and info["xl"] is True
    status, _, frame = call(base, f"/api/frame?run={info['run']}&t=0")
    assert status == 200 and len(frame["sugar"]) == 250_000


def test_post_without_xl_is_regular(live_server):
    status, _, info = call(live_server, "/api/run", {"experiment": "II-4", "seed": 0})
    assert status == 200 and info["xl"] is False


@pytest.mark.parametrize("bad", ["yes", 1, None])
def test_post_rejects_a_non_boolean_xl(live_server, bad):
    status, _, _ = call(live_server, "/api/run", {"experiment": "II-4", "seed": 0, "xl": bad})
    assert status == 400
