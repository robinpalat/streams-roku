#!/usr/bin/env python3
"""Build local catalog, EPG, coverage and latest.json artifacts.

This is intentionally a local-only pipeline. It does not publish anywhere.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from .catalog import CatalogBuilder
from .coverage import build_coverage
from .m3u import parse_m3u, validate_m3u
from .xmltv import parse_xmltv_files

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG = ROOT / "pipeline" / "config" / "sources.json"
DEFAULT_OUT = ROOT / "pipeline" / "out"


def read_text(value: str, base: Path) -> str:
    if value.startswith(("http://", "https://")):
        request = urllib.request.Request(value, headers={"User-Agent": "StreamsRoku/1.0"})
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read().decode("utf-8", errors="replace")
    path = Path(value)
    if not path.is_absolute():
        candidate = (base / path)
        if candidate.exists():
            path = candidate
        else:
            path = ROOT / path
    return path.read_text(encoding="utf-8", errors="replace")


def resolve_path(value: str, base: Path) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    candidate = base / path
    if candidate.exists():
        return candidate
    return ROOT / path


def write_json(path: Path, value) -> bytes:
    data = json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_now(value: str | None) -> int:
    if not value:
        return int(datetime.now(timezone.utc).timestamp())
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    return int(datetime.fromisoformat(text).timestamp())


def slug(value: str) -> str:
    value = re.sub(r"[^a-zA-Z0-9._-]+", "_", value.strip().lower())
    return value or "other"


def build_source(source: dict, config_dir: Path, out_root: Path, now: int,
                 shard_threshold: int) -> dict:
    source_id = str(source.get("id") or "default")
    name = source.get("name") or source_id
    m3u_value = source.get("m3u") or source.get("url")
    if not m3u_value:
        raise ValueError(f"source {source_id}: missing m3u")

    text = read_text(m3u_value, config_dir)
    validation = validate_m3u(text)
    if not validation.ok:
        raise ValueError(f"source {source_id}: invalid M3U: {validation.reason}")
    items = validation.items

    epg_values = source.get("epg") or []
    if isinstance(epg_values, str):
        epg_values = [epg_values]
    epg_paths = [resolve_path(v, config_dir) for v in epg_values if not str(v).startswith(("http://", "https://"))]
    epg = parse_xmltv_files(epg_paths, now) if epg_paths else {
        "schema": 1, "generatedAt": now, "windowStart": now - 21600,
        "windowEnd": now + 86400, "channels": {},
    }

    data_cfg = source.get("data") or {}
    builder = CatalogBuilder(
        resolve_path(data_cfg["channels"], config_dir) if data_cfg.get("channels") else None,
        resolve_path(data_cfg["feeds"], config_dir) if data_cfg.get("feeds") else None,
        resolve_path(data_cfg["logos"], config_dir) if data_cfg.get("logos") else None,
        resolve_path(data_cfg["aliases"], config_dir) if data_cfg.get("aliases") else None,
    )
    catalog = builder.build(source_id, items, epg, now)
    coverage = build_coverage(source_id, items, catalog, epg, source.get("failed") or [], now,
                              source.get("errors") or [])

    out_dir = out_root / slug(source_id)
    out_dir.mkdir(parents=True, exist_ok=True)

    catalog_bytes = write_json(out_dir / "catalog.json", catalog)
    catalog_hash = sha(catalog_bytes)
    catalog_version = "c-" + catalog_hash[:16]
    catalog["version"] = catalog_version
    catalog_bytes = write_json(out_dir / "catalog.json", catalog)
    catalog_hash = sha(catalog_bytes)

    epg.pop("version", None)
    epg_bytes = write_json(out_dir / "epg.json", epg)
    epg_hash = sha(epg_bytes)
    epg_version = "e-" + epg_hash[:16]
    epg["version"] = epg_version
    epg_bytes = write_json(out_dir / "epg.json", epg)
    epg_hash = sha(epg_bytes)

    epg_entry = {
        "version": epg_version,
        "file": "epg.json",
        "hash": epg_hash,
        "size": len(epg_bytes),
    }

    if len(epg_bytes) > shard_threshold and len(epg["channels"]) > 1:
        group_for: dict[str, str] = {}
        for item in items:
            if item.tvg_id and item.tvg_id not in group_for:
                group_for[item.tvg_id] = item.group or "other"
        shards: dict[str, dict] = {}
        for cid, channel in epg["channels"].items():
            g = group_for.get(cid, "other")
            shards.setdefault(g, {})[cid] = channel
        if len(shards) > 1:
            files = []
            for group, channels in sorted(shards.items()):
                shard = dict(epg)
                shard["version"] = epg_version
                shard["channels"] = channels
                shard_name = f"epg_{slug(group)}.json"
                shard_bytes = write_json(out_dir / shard_name, shard)
                shard_hash = sha(shard_bytes)
                files.append({
                    "version": "e-" + shard_hash[:16],
                    "file": shard_name,
                    "hash": shard_hash,
                    "size": len(shard_bytes),
                    "group": group,
                })
            (out_dir / "epg.json").unlink(missing_ok=True)
            epg_entry = {"version": epg_version, "files": files, "sharded": True}

    coverage_bytes = write_json(out_dir / "coverage.json", coverage)
    coverage_hash = sha(coverage_bytes)

    manifest = {
        "schema": 1,
        "version": "m-" + sha((catalog_hash + epg_hash + coverage_hash).encode())[:16],
        "generatedAt": now,
        "refreshAfter": now + 3600,
        "windowStart": epg.get("windowStart"),
        "windowEnd": epg.get("windowEnd"),
        "catalog": {
            "version": catalog_version,
            "file": "catalog.json",
            "hash": catalog_hash,
            "size": len(catalog_bytes),
        },
        "epg": epg_entry,
        "coverage": {
            "file": "coverage.json",
            "hash": coverage_hash,
            "size": len(coverage_bytes),
        },
    }
    write_json(out_dir / "latest.json", manifest)
    return {
        "sourceId": source_id,
        "name": name,
        "outDir": str(out_dir),
        "channels": len(items),
        "mapped": coverage["totals"]["mapped"],
        "withPrograms": coverage["totals"]["withPrograms"],
        "manifest": manifest,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build local Roku metadata artifacts")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG))
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--now", default=None, help="ISO-8601 timestamp; fixed timestamps make fixtures reproducible")
    parser.add_argument("--shard-threshold", type=int, default=400_000)
    parser.add_argument("--source", default=None, help="only build this source id")
    args = parser.parse_args(argv)

    config_path = Path(args.config)
    if not config_path.exists():
        print(f"config not found: {config_path}", file=sys.stderr)
        return 2
    config = json.loads(config_path.read_text(encoding="utf-8"))
    sources = config.get("sources") or []
    if not sources:
        print("no sources configured", file=sys.stderr)
        return 2
    now = parse_now(args.now)
    out_root = Path(args.out)
    results = []
    for source in sources:
        if args.source and str(source.get("id")) != args.source:
            continue
        try:
            result = build_source(source, config_path.parent, out_root, now, args.shard_threshold)
            results.append(result)
            print(f"built {result['sourceId']}: {result['channels']} channels, "
                  f"{result['mapped']} mapped, {result['withPrograms']} with EPG -> {result['outDir']}")
        except Exception as exc:  # noqa: BLE001 - CLI should report all source failures
            print(f"source failed: {source.get('id')}: {exc}", file=sys.stderr)
            return 1
    if not results:
        print("no source built", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
