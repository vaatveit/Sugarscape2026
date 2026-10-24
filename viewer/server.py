"""Local HTTP server for the viewer: a small JSON API over one `Run`, plus the static page.

Standard library only. Binds 127.0.0.1, so only this machine can reach it.
"""

import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

from viewer.run import OutOfRange, Run, catalog

STATIC = (Path(__file__).parent / "static").resolve()
# Fixed table: on Windows, mimetypes can report .js/.mjs as text/plain from the registry, and browsers then
# refuse to load them as modules.
CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
}


class ApiError(Exception):
    def __init__(self, status: HTTPStatus, message: str) -> None:
        super().__init__(message)
        self.status = status


def _int(query: dict, name: str) -> int:
    try:
        value = int(query[name][0])
    except (KeyError, ValueError):
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{name} must be an integer")
    if value < 0:
        raise ApiError(HTTPStatus.BAD_REQUEST, f"{name} must be >= 0")
    return value


class Handler(BaseHTTPRequestHandler):
    server: "ViewerServer"

    def log_message(self, format, *args):  # keep the console to the URL and errors
        pass

    # --- responses -----------------------------------------------------------------------

    def _send(self, status: HTTPStatus, body: bytes, content_type: str, no_store: bool = False) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        if no_store:
            self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: HTTPStatus, value) -> None:
        self._send(status, json.dumps(value).encode(), "application/json", no_store=True)

    def _file(self, name: str) -> None:
        path = (STATIC / unquote(name)).resolve()
        if not name or path.parent != STATIC or not path.is_file() or path.suffix not in CONTENT_TYPES:
            raise ApiError(HTTPStatus.NOT_FOUND, "not found")
        self._send(HTTPStatus.OK, path.read_bytes(), CONTENT_TYPES[path.suffix])

    # --- routes --------------------------------------------------------------------------

    def do_GET(self) -> None:
        self._dispatch(self._get)

    def do_POST(self) -> None:
        self._dispatch(self._post)

    def _dispatch(self, route) -> None:
        try:
            route(urlsplit(self.path))
        except ApiError as e:
            self._json(e.status, {"error": str(e)})
        except Exception as e:  # the model raised: report it and keep serving
            self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": f"{type(e).__name__}: {e}"})

    def _get(self, url) -> None:
        query = parse_qs(url.query)
        if url.path == "/":
            self._file("index.html")
        elif url.path.startswith("/static/"):
            self._file(url.path[len("/static/"):])
        elif url.path == "/api/experiments":
            self._json(HTTPStatus.OK, catalog())
        elif url.path == "/api/frame":
            run = self._run()
            t = _int(query, "t")
            try:
                frame = run.frame(t)
            except OutOfRange as e:
                raise ApiError(HTTPStatus.BAD_REQUEST, str(e))
            self._json(HTTPStatus.OK, {**frame.to_json(), "latest": run.latest})
        elif url.path == "/api/population":
            run = self._run()
            start = _int(query, "from")
            self._json(HTTPStatus.OK, {"latest": run.latest, "from": start, "counts": run.populations(start)})
        else:
            raise ApiError(HTTPStatus.NOT_FOUND, "not found")

    def _post(self, url) -> None:
        if url.path != "/api/run":
            raise ApiError(HTTPStatus.NOT_FOUND, "not found")
        try:
            body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            exp_id, seed = body["experiment"], body["seed"]
        except (ValueError, KeyError, TypeError):
            raise ApiError(HTTPStatus.BAD_REQUEST, 'body must be {"experiment": id, "seed": k}')
        try:
            run = Run(exp_id, seed)
        except ValueError as e:
            raise ApiError(HTTPStatus.BAD_REQUEST, str(e))
        self.server.run = run
        self._json(HTTPStatus.OK, run.info())

    def _run(self) -> Run:
        if self.server.run is None:
            raise ApiError(HTTPStatus.CONFLICT, "no run started")
        return self.server.run


class ViewerServer(ThreadingHTTPServer):
    daemon_threads = True
    run: Run | None = None


def make_server(port: int = 0) -> ViewerServer:
    return ViewerServer(("127.0.0.1", port), Handler)
