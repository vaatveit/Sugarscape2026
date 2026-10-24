"""python -m viewer [--port N] [--no-browser]"""

import argparse
import webbrowser

from viewer.server import make_server


def main() -> None:
    parser = argparse.ArgumentParser(prog="python -m viewer", description="Watch a Sugarscape run in the browser.")
    parser.add_argument("--port", type=int, default=0, help="port to serve on (default: a free one)")
    parser.add_argument("--no-browser", action="store_true", help="don't open a browser tab")
    args = parser.parse_args()
    server = make_server(args.port)
    url = "http://127.0.0.1:%d/" % server.server_address[1]
    print(f"Sugarscape viewer at {url}  (Ctrl+C to stop)", flush=True)
    if not args.no_browser:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
