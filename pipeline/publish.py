#!/usr/bin/env python3
"""Prepare and validate the static GitHub Pages artifact for Roku.

Only the compact Roku contract is published. The M3U streamMap and grabber
diagnostics never leave the build directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

from .validate import validate

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE = ROOT / "pipeline" / "out" / "real"
DEFAULT_DEST = ROOT / "_site"


class PublicationError(RuntimeError):
    pass


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        raise PublicationError(f"invalid JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise PublicationError(f"JSON root is not an object: {path}")
    return value


def write_json(path: Path, value) -> bytes:
    data = json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


def public_catalog(catalog: dict) -> dict:
    channels = {}
    for cid, ch in (catalog.get("channels") or {}).items():
        if not isinstance(ch, dict):
            continue
        item = {}
        for key in ("channel", "feed", "name", "logo", "epgId"):
            if ch.get(key) not in (None, ""):
                item[key] = ch[key]
        if item:
            channels[cid] = item
    return {
        "schema": catalog.get("schema", 1),
        "sourceId": catalog.get("sourceId", ""),
        "generatedAt": catalog.get("generatedAt", 0),
        "logoBase": catalog.get("logoBase", ""),
        "placeholder": catalog.get("placeholder", ""),
        "channels": channels,
    }


def public_coverage(coverage: dict) -> dict:
    details = {}
    for cid, ch in (coverage.get("channels") or {}).items():
        if not isinstance(ch, dict):
            continue
        item = {}
        for key in ("tvgId", "name", "status", "programCount", "unknownDurationCount", "endKnown"):
            if ch.get(key) is not None:
                item[key] = ch[key]
        if item:
            details[cid] = item
    return {
        "schema": coverage.get("schema", 1),
        "sourceId": coverage.get("sourceId", ""),
        "generatedAt": coverage.get("generatedAt", 0),
        "totals": coverage.get("totals") or {},
        "coverage": coverage.get("coverage") or {},
        "channels": details,
    }


def read_public_epg(real: Path, manifest: dict) -> dict:
    info = manifest.get("epg") or {}
    files = info.get("files") if isinstance(info.get("files"), list) else None
    if files:
        merged = {"channels": {}}
        for entry in files:
            shard = read_json(real / str(entry.get("file") or ""))
            merged["channels"].update(shard.get("channels") or {})
        return merged
    return read_json(real / str(info.get("file") or "epg.json"))


def epg_program_count(epg: dict) -> int:
    total = 0
    for ch in (epg.get("channels") or {}).values():
        total += len((ch or {}).get("programs") or [])
    return total


def epg_channel_count(epg: dict) -> int:
    return len(epg.get("channels") or {})


def load_previous_coverage(previous: Path | None) -> dict | None:
    if previous is None:
        return None
    candidates = [previous / "coverage.json", previous / "real" / "coverage.json"]
    for path in candidates:
        if path.exists():
            return read_json(path)
    return None


def check_publication_guard(new_coverage: dict, new_epg: dict, previous: dict | None,
                            min_coverage_ratio: float = 0.85,
                            min_program_ratio: float = 0.75,
                            allow_channel_loss: bool = False) -> None:
    new_totals = new_coverage.get("totals") or {}
    new_with = int(new_totals.get("withPrograms") or 0)
    new_programs = epg_program_count(new_epg)
    if new_with <= 0 or epg_channel_count(new_epg) <= 0 or new_programs <= 0:
        raise PublicationError("generation is empty: no channels/programmes")
    if not previous:
        return
    old_totals = previous.get("totals") or {}
    old_with = int(old_totals.get("withPrograms") or 0)
    old_program_count = 0
    for ch in (previous.get("channels") or {}).values():
        old_program_count += int((ch or {}).get("programCount") or 0)
    if old_with > 0 and new_with < old_with * min_coverage_ratio:
        raise PublicationError(
            f"coverage regression: withPrograms {new_with} < {old_with} * {min_coverage_ratio}"
        )
    if old_program_count > 0 and new_programs < old_program_count * min_program_ratio:
        raise PublicationError(
            f"programme regression: {new_programs} < {old_program_count} * {min_program_ratio}"
        )
    old_ids = {
        cid for cid, ch in (previous.get("channels") or {}).items()
        if (ch or {}).get("status") == "with_programs"
    }
    new_ids = {
        cid for cid, ch in (new_coverage.get("channels") or {}).items()
        if (ch or {}).get("status") == "with_programs"
    }
    lost = sorted(old_ids - new_ids)
    if lost and not allow_channel_loss:
        raise PublicationError(
            "programming lost for previously covered channels: " + ", ".join(lost[:12])
        )


def _assert_no_sensitive(value, path: str = "") -> None:
    forbidden = {"streammap", "url", "m3u", "password", "token", "secret", "authorization"}
    if isinstance(value, dict):
        for key, child in value.items():
            low = str(key).lower()
            if low in forbidden:
                raise PublicationError(f"sensitive key in public artifact: {path}/{key}")
            _assert_no_sensitive(child, f"{path}/{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _assert_no_sensitive(child, f"{path}[{index}]")
    elif isinstance(value, str):
        low = value.lower()
        for marker in ("http://192.168.", "http://127.", "http://localhost", "file://", "/home/"):
            if marker in low:
                raise PublicationError(f"private location in public artifact: {path}")


def validate_public(dest: Path) -> None:
    real = dest / "real"
    errors = validate(real)
    if errors:
        raise PublicationError("; ".join(errors))
    index = dest / "index.html"
    if not index.exists():
        raise PublicationError("missing index.html")
    manifest = read_json(real / "latest.json")
    catalog = read_json(real / "catalog.json")
    epg = read_public_epg(real, manifest)
    coverage = read_json(real / "coverage.json")
    if catalog.get("streamMap") is not None:
        raise PublicationError("streamMap must not be published")
    if not catalog.get("channels"):
        raise PublicationError("catalog has no channels")
    if not epg.get("channels"):
        raise PublicationError("epg has no channels")
    if not coverage.get("totals") or not coverage.get("coverage"):
        raise PublicationError("coverage totals missing")
    if not manifest.get("catalog") or not manifest.get("epg") or not manifest.get("coverage"):
        raise PublicationError("manifest references missing")
    for relative in (Path("real/latest.json"), Path("real/catalog.json"), Path("real/coverage.json")):
        _assert_no_sensitive(read_json(dest / relative), str(relative))
    _assert_no_sensitive(epg, "real/epg")


def prepare(source: Path, dest: Path, previous: Path | None = None,
            min_coverage_ratio: float = 0.85,
            min_program_ratio: float = 0.75,
            allow_channel_loss: bool = False) -> dict:
    source = source.resolve()
    dest = dest.resolve()
    errors = validate(source)
    if errors:
        raise PublicationError("source artifacts invalid: " + "; ".join(errors))

    manifest = read_json(source / "latest.json")
    catalog = public_catalog(read_json(source / "catalog.json"))
    coverage = public_coverage(read_json(source / "coverage.json"))
    epg_info = manifest.get("epg") or {}
    epg_files = []
    if isinstance(epg_info.get("files"), list):
        epg_files = [str(entry.get("file") or "") for entry in epg_info["files"]]
    else:
        epg_files = [str(epg_info.get("file") or "epg.json")]
    epg_files = [name for name in epg_files if name]
    if not epg_files:
        raise PublicationError("manifest has no EPG files")

    epg = None
    if len(epg_files) == 1 and epg_files[0] == "epg.json":
        epg = read_json(source / "epg.json")
    else:
        merged = {"channels": {}}
        for name in epg_files:
            shard = read_json(source / name)
            merged["channels"].update(shard.get("channels") or {})
        epg = merged
    check_publication_guard(
        coverage, epg, load_previous_coverage(previous),
        min_coverage_ratio, min_program_ratio, allow_channel_loss,
    )

    stage = dest.parent / (dest.name + ".staging")
    if stage.exists():
        shutil.rmtree(stage)
    stage.mkdir(parents=True)
    try:
        real = stage / "real"
        real.mkdir()
        catalog_bytes = write_json(real / "catalog.json", catalog)
        catalog_hash = sha(catalog_bytes)
        catalog["version"] = "c-" + catalog_hash[:16]
        catalog_bytes = write_json(real / "catalog.json", catalog)
        catalog_hash = sha(catalog_bytes)

        coverage_bytes = write_json(real / "coverage.json", coverage)
        coverage_hash = sha(coverage_bytes)

        for name in epg_files:
            src = source / name
            target = real / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, target)
            if epg_info.get("hash") and len(epg_files) == 1:
                if sha(target.read_bytes()) != epg_info["hash"]:
                    raise PublicationError(f"EPG hash changed while preparing {name}")

        epg_hash = str(epg_info.get("hash") or "")
        if not epg_hash:
            epg_hash = sha(json.dumps(epg_info, sort_keys=True, separators=(",", ":")).encode())

        new_manifest = dict(manifest)
        new_manifest["catalog"] = {
            "version": catalog.get("version", "c-" + catalog_hash[:16]),
            "file": "catalog.json",
            "hash": catalog_hash,
            "size": len(catalog_bytes),
        }
        new_manifest["coverage"] = {
            "file": "coverage.json",
            "hash": coverage_hash,
            "size": len(coverage_bytes),
        }
        new_manifest["version"] = "m-" + sha((catalog_hash + epg_hash + coverage_hash).encode())[:16]
        write_json(real / "latest.json", new_manifest)

        links = ["latest.json", "catalog.json", "coverage.json"] + epg_files
        items = "".join(f'<li><a href="real/{name}">{name}</a></li>' for name in links)
        (stage / "index.html").write_text(
            "<!doctype html><html lang=\"es\"><meta charset=\"utf-8\">"
            "<title>Streams EPG</title><body><h1>Streams EPG</h1>"
            "<p>Artefactos públicos de metadatos para la app Roku.</p>"
            f"<ul>{items}</ul></body></html>",
            encoding="utf-8",
        )
        validate_public(stage)
    except Exception:
        shutil.rmtree(stage, ignore_errors=True)
        raise

    backup = dest.parent / (dest.name + ".previous")
    if backup.exists():
        shutil.rmtree(backup)
    if dest.exists():
        dest.rename(backup)
    try:
        stage.rename(dest)
    except Exception:
        if backup.exists() and not dest.exists():
            backup.rename(dest)
        shutil.rmtree(stage, ignore_errors=True)
        raise
    if backup.exists():
        shutil.rmtree(backup)
    return {
        "dest": str(dest),
        "catalogVersion": catalog.get("version", ""),
        "coverage": coverage.get("totals", {}),
        "epgFiles": epg_files,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Prepare static Pages artifact")
    parser.add_argument("--source", default=str(DEFAULT_SOURCE))
    parser.add_argument("--dest", default=str(DEFAULT_DEST))
    parser.add_argument("--previous", default="", help="previous publication directory")
    parser.add_argument("--min-coverage-ratio", type=float, default=0.85)
    parser.add_argument("--min-program-ratio", type=float, default=0.75)
    parser.add_argument("--allow-channel-loss", action="store_true")
    args = parser.parse_args(argv)
    try:
        result = prepare(
            Path(args.source), Path(args.dest), Path(args.previous) if args.previous else None,
            args.min_coverage_ratio, args.min_program_ratio, args.allow_channel_loss,
        )
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    print(f"published to {result['dest']}")
    print(f"catalogVersion={result['catalogVersion']} epgFiles={len(result['epgFiles'])}")
    print(json.dumps(result["coverage"], sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
