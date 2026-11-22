#!/usr/bin/env python3
"""Validate generated local artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check_file(base: Path, entry: dict, label: str) -> list[str]:
    errors = []
    path = base / entry.get("file", "")
    if not path.exists():
        return [f"{label}: missing {path}"]
    data = path.read_bytes()
    if entry.get("hash") and sha(data) != entry["hash"]:
        errors.append(f"{label}: hash mismatch")
    if entry.get("size") is not None and len(data) != entry["size"]:
        errors.append(f"{label}: size mismatch")
    try:
        parsed = json.loads(data)
    except Exception as exc:  # noqa: BLE001
        return errors + [f"{label}: invalid JSON: {exc}"]
    if label.startswith("catalog") and not isinstance(parsed.get("channels"), dict):
        errors.append("catalog: channels missing")
    if label.startswith("epg") and not isinstance(parsed.get("channels"), dict):
        errors.append("epg: channels missing")
    return errors


def validate(base: Path) -> list[str]:
    errors = []
    manifest_path = base / "latest.json"
    if not manifest_path.exists():
        return [f"missing {manifest_path}"]
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        return [f"latest.json invalid: {exc}"]
    if manifest.get("schema") != 1:
        errors.append("manifest: schema != 1")
    catalog = manifest.get("catalog")
    if not isinstance(catalog, dict):
        errors.append("manifest: catalog missing")
    else:
        errors.extend(check_file(base, catalog, "catalog"))
    epg = manifest.get("epg")
    if not isinstance(epg, dict):
        errors.append("manifest: epg missing")
    elif isinstance(epg.get("files"), list):
        for index, entry in enumerate(epg["files"]):
            errors.extend(check_file(base, entry, f"epg[{index}]"))
    else:
        errors.extend(check_file(base, epg, "epg"))
    cov = manifest.get("coverage")
    if isinstance(cov, dict):
        errors.extend(check_file(base, cov, "coverage"))
        cov_path = base / cov.get("file", "coverage.json")
        if cov_path.exists():
            try:
                coverage = json.loads(cov_path.read_text(encoding="utf-8"))
                if "coverage" not in coverage or "potentialMapping" not in coverage["coverage"]:
                    errors.append("coverage: effective/potential fields missing")
            except Exception as exc:  # noqa: BLE001
                errors.append(f"coverage: invalid JSON: {exc}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    base = Path(args.out)
    errors = validate(base)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(f"OK: {base}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
