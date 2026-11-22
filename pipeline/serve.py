#!/usr/bin/env python3
"""Serve locally generated artifacts for Roku testing. Local only; no publish."""

from __future__ import annotations

import argparse
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default="pipeline/out")
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--bind", default="0.0.0.0")
    args = parser.parse_args()
    base = Path(args.dir).resolve()
    if not base.exists():
        print(f"directory not found: {base}")
        return 2
    handler = functools.partial(SimpleHTTPRequestHandler, directory=str(base))
    server = ThreadingHTTPServer((args.bind, args.port), handler)
    print(f"serving {base} at http://{args.bind}:{args.port}/")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
