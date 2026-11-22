#!/usr/bin/env python3
"""Local wrapper around iptv-org/epg grabbers.

This never publishes or schedules anything. It only invokes the external
grabber from a local checkout and writes XMLTV into a local output path.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Run iptv-org/epg locally")
    parser.add_argument("--epg-repo", required=True, help="path to a local iptv-org/epg checkout")
    parser.add_argument("--out", required=True, help="local output XMLTV path")
    parser.add_argument("--sites", default="", help="comma-separated sites, e.g. mi.tv,gatotv.com")
    parser.add_argument("--channels", default="", help="optional local *.channels.xml path")
    parser.add_argument("--days", type=int, default=2)
    parser.add_argument("--timeout", type=int, default=30000)
    args = parser.parse_args()

    repo = Path(args.epg_repo)
    if not (repo / "package.json").exists():
        print(f"not an epg checkout: {repo}", file=sys.stderr)
        return 2
    if not args.sites and not args.channels:
        print("provide --sites or --channels", file=sys.stderr)
        return 2
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    command = ["npm", "run", "grab", "---", f"--output={out}", f"--days={args.days}", f"--timeout={args.timeout}"]
    if args.sites:
        command.append(f"--sites={args.sites}")
    if args.channels:
        command.append(f"--channels={args.channels}")
    print("running:", " ".join(command), "in", repo)
    result = subprocess.run(command, cwd=repo)
    if result.returncode != 0:
        print(f"grabber failed with exit code {result.returncode}", file=sys.stderr)
        return result.returncode
    if not out.exists() or out.stat().st_size == 0:
        print(f"grabber produced no XMLTV: {out}", file=sys.stderr)
        return 1
    print(f"XMLTV written: {out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
