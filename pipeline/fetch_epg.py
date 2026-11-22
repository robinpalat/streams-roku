#!/usr/bin/env python3
"""Download configured XMLTV guides and prepare a runtime sources config.

This keeps the existing generator. It only runs the iptv-org/epg grabbers that
already produced the local snapshots, records every grabber result, and writes a
sources config that references only successfully generated XMLTV files.
"""

from __future__ import annotations

import argparse
import copy
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_EPG_CONFIG = ROOT / "pipeline" / "config" / "epg_sources.json"
DEFAULT_SOURCES = ROOT / "pipeline" / "config" / "sources.json"
DEFAULT_OUT = ROOT / "pipeline" / "out" / "xmltv"
DEFAULT_STATUS = ROOT / "pipeline" / "out" / "grabber-status.json"
DEFAULT_GENERATED = ROOT / "pipeline" / "out" / "sources.generated.json"


def project_path(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else ROOT / path


def run_grabber(epg_repo: Path, channels: Path, output: Path, days: int,
                timeout: int) -> subprocess.CompletedProcess:
    command = [
        sys.executable, "-m", "pipeline.grab_epg",
        "--epg-repo", str(epg_repo),
        "--channels", str(channels),
        "--out", str(output),
        "--days", str(days),
        "--timeout", str(timeout),
    ]
    return subprocess.run(command, cwd=str(ROOT), text=True, capture_output=True)


def error_text(result: subprocess.CompletedProcess) -> str:
    text = (result.stderr or result.stdout or "").strip()
    return text[-1200:] or "grabber failed without output"


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def fetch(epg_config: dict, sources_config: dict, epg_repo: Path, out_dir: Path,
          source_id: str = "real", runner=run_grabber) -> tuple[dict, dict, bool]:
    sources = sources_config.get("sources") or []
    source = next((s for s in sources if str(s.get("id")) == source_id), None)
    if source is None:
        raise ValueError(f"source {source_id} not found in sources config")

    out_dir.mkdir(parents=True, exist_ok=True)
    days = int(epg_config.get("days") or 2)
    timeout = int(epg_config.get("timeout") or 30000)
    results = []
    successful = []
    required_ok = True

    for item in epg_config.get("sources") or []:
        sid = str(item.get("id") or "unknown")
        required = bool(item.get("required", True))
        channels = project_path(str(item.get("channels") or ""))
        output = out_dir / str(item.get("output") or f"guide-{sid}.xml")
        output.unlink(missing_ok=True)
        entry = {
            "id": sid,
            "required": required,
            "channels": str(channels.relative_to(ROOT)) if channels.is_relative_to(ROOT) else str(channels),
            "output": output.name,
            "status": "failed",
            "exitCode": None,
            "bytes": 0,
        }
        if not channels.exists():
            entry["error"] = f"channels file not found: {channels}"
            results.append(entry)
            if required:
                required_ok = False
            continue
        try:
            result = runner(epg_repo, channels, output, days, timeout)
            entry["exitCode"] = result.returncode
            if result.returncode == 0 and output.exists() and output.stat().st_size > 0:
                entry["status"] = "ok"
                entry["bytes"] = output.stat().st_size
                successful.append(output)
            else:
                entry["error"] = error_text(result)
                if required:
                    required_ok = False
        except Exception as exc:  # noqa: BLE001 - every grabber failure must be recorded
            entry["error"] = str(exc)
            if required:
                required_ok = False
        results.append(entry)

    generated = copy.deepcopy(sources_config)
    target = next((s for s in generated.get("sources") or [] if str(s.get("id")) == source_id), None)
    target["epg"] = [str(p) for p in successful]
    if epg_config.get("m3u"):
        target["m3u"] = epg_config["m3u"]
    existing_errors = list(target.get("errors") or [])
    for result in results:
        if result["status"] == "failed":
            existing_errors.append({
                "site": result["id"],
                "channel": "",
                "error": result.get("error", "grabber failed"),
                "result": "other sources used" if not result["required"] else "build blocked",
            })
    target["errors"] = existing_errors

    status = {
        "schema": 1,
        "generatedAt": int(datetime.now(timezone.utc).timestamp()),
        "source": source_id,
        "epgRepository": epg_config.get("epgRepository", ""),
        "ok": required_ok,
        "sources": results,
    }
    return generated, status, required_ok


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Download configured XMLTV guides")
    parser.add_argument("--config", default=str(DEFAULT_EPG_CONFIG))
    parser.add_argument("--sources-config", default=str(DEFAULT_SOURCES))
    parser.add_argument("--epg-repo", required=True)
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT))
    parser.add_argument("--status", default=str(DEFAULT_STATUS))
    parser.add_argument("--generated-config", default=str(DEFAULT_GENERATED))
    parser.add_argument("--source-id", default="real")
    args = parser.parse_args(argv)

    epg_config = load_json(Path(args.config))
    sources_config = load_json(Path(args.sources_config))
    epg_repo = Path(args.epg_repo).resolve()
    if not epg_repo.exists():
        print(f"EPG repository not found: {epg_repo}", file=sys.stderr)
        return 2
    generated, status, ok = fetch(
        epg_config, sources_config, epg_repo, Path(args.out_dir), args.source_id,
    )
    write_json(Path(args.status), status)
    for result in status["sources"]:
        print(f"{result['status']:6} {result['id']:10} {result['bytes']:>8} bytes")
    if not ok:
        print("required grabber failed; publication blocked", file=sys.stderr)
        return 1
    if not generated["sources"] or not next(
        (s for s in generated["sources"] if s.get("id") == args.source_id), {}
    ).get("epg"):
        print("no XMLTV output produced; publication blocked", file=sys.stderr)
        return 1
    write_json(Path(args.generated_config), generated)
    print(f"generated config: {args.generated_config}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
