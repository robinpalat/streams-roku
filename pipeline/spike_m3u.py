#!/usr/bin/env python3
"""Generate a synthetic M3U for the LabelList logo spike. Local testing only."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=2000)
    parser.add_argument("--logo-base", default="http://192.168.1.7:8000/spike/logo.png")
    parser.add_argument("--out", default="pipeline/fixtures/spike.m3u")
    args = parser.parse_args()
    lines = ["#EXTM3U"]
    for i in range(1, args.count + 1):
        logo = f"{args.logo_base}?i={i}"
        lines.append(f'#EXTINF:-1 tvg-id="Spike{i}.us@SD" tvg-logo="{logo}" group-title="Spike",Spike {i}')
        lines.append(f"https://example.invalid/spike/{i}.m3u8")
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {args.count} channels to {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
