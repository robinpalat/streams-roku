"""Measure effective EPG coverage; never report potential mapping as effective."""

from __future__ import annotations

from typing import Iterable

from .m3u import Channel


def build_coverage(source_id: str, items: Iterable[Channel], catalog: dict, epg: dict,
                   failed: Iterable[str] = (), generated_at: int = 0,
                   source_errors: Iterable[dict] = ()) -> dict:
    failed_set = {str(v) for v in failed}
    catalog_channels = (catalog or {}).get("channels", {})
    epg_channels = (epg or {}).get("channels", {})
    details: dict[str, dict] = {}
    counts = {
        "sourceChannels": 0,
        "mapped": 0,
        "withPrograms": 0,
        "withoutPrograms": 0,
        "unknownDuration": 0,
        "partial": 0,
        "failed": 0,
        "notMapped": 0,
    }
    seen: set[str] = set()
    for item in items:
        counts["sourceChannels"] += 1
        tvg_id = item.tvg_id
        if not tvg_id:
            counts["notMapped"] += 1
            details[f"url:{item.url}"] = {
                "tvgId": "",
                "name": item.name,
                "status": "not_mapped",
                "reason": "no_tvg_id",
            }
            continue
        if tvg_id in seen:
            continue
        seen.add(tvg_id)
        if tvg_id not in catalog_channels:
            counts["notMapped"] += 1
            details[tvg_id] = {"tvgId": tvg_id, "name": item.name, "status": "not_mapped",
                               "reason": "not_in_catalog"}
            continue
        counts["mapped"] += 1
        if tvg_id in failed_set:
            counts["failed"] += 1
            details[tvg_id] = {"tvgId": tvg_id, "name": item.name, "status": "failed"}
            continue
        channel = epg_channels.get(tvg_id)
        if not channel:
            counts["withoutPrograms"] += 1
            details[tvg_id] = {"tvgId": tvg_id, "name": item.name, "status": "without_programs"}
            continue
        programs = channel.get("programs") or []
        if not programs:
            counts["withoutPrograms"] += 1
            details[tvg_id] = {"tvgId": tvg_id, "name": item.name, "status": "without_programs"}
            continue
        counts["withPrograms"] += 1
        unknown = int(channel.get("unknownDurationCount") or 0)
        if unknown:
            counts["unknownDuration"] += 1
        if not channel.get("endKnown"):
            counts["partial"] += 1
        details[tvg_id] = {
            "tvgId": tvg_id,
            "name": item.name,
            "status": "with_programs",
            "programCount": len(programs),
            "unknownDurationCount": unknown,
            "endKnown": bool(channel.get("endKnown")),
        }

    total = counts["sourceChannels"] or 1
    return {
        "schema": 1,
        "sourceId": source_id,
        "generatedAt": generated_at,
        "totals": counts,
        "coverage": {
            "potentialMapping": counts["mapped"] / total,
            "effective": counts["withPrograms"] / total,
        },
        "sourceErrors": list(source_errors),
        "channels": details,
    }
