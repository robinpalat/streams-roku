"""XMLTV to compact 24h+6h EPG JSON conversion."""

from __future__ import annotations

import calendar
import re
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterable

TIME_RE = re.compile(r"^(\d{14})\s*([+-]\d{4})?$")


def parse_xmltv_time(value: str) -> int | None:
    if not value:
        return None
    match = TIME_RE.match(value.strip())
    if not match:
        return None
    raw = match.group(1)
    offset = match.group(2)
    try:
        dt = datetime.strptime(raw, "%Y%m%d%H%M%S")
    except ValueError:
        return None
    if offset:
        sign = 1 if offset[0] == "+" else -1
        hours = int(offset[1:3])
        minutes = int(offset[3:5])
        dt = dt.replace(tzinfo=timezone(sign * timedelta(hours=hours, minutes=minutes)))
    else:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp())


def _text(node: ET.Element, tag: str) -> str:
    child = node.find(tag)
    if child is None or child.text is None:
        return ""
    return child.text.strip()


def _episode(node: ET.Element) -> str:
    child = node.find("episode-num")
    if child is None or child.text is None:
        return ""
    return child.text.strip()


def _icon(node: ET.Element) -> str:
    child = node.find("icon")
    if child is None:
        return ""
    return child.attrib.get("src", "").strip()


def parse_xmltv_files(paths: Iterable[str | Path], now: int, before_seconds: int = 6 * 3600,
                      after_seconds: int = 24 * 3600) -> dict:
    """Parse XMLTV files and keep one source per channel.

    When the same channel id appears in several files, the source with the
    largest number of valid programmes wins. Ties keep the first file. This
    prevents duplicate programmes when several sites cover the same channel.
    """
    window_start = now - before_seconds
    window_end = now + after_seconds
    best: dict[str, dict] = {}

    for file_index, path in enumerate(paths):
        local: dict[str, dict] = {}
        root = ET.parse(str(path)).getroot()
        for ch in root.findall("channel"):
            cid = ch.attrib.get("id", "").strip()
            if not cid:
                continue
            if cid not in local:
                local[cid] = {
                    "name": _text(ch, "display-name"),
                    "icon": _icon(ch),
                    "programs": [],
                    "fileIndex": file_index,
                }
            elif not local[cid]["name"]:
                local[cid]["name"] = _text(ch, "display-name")

        for prog in root.findall("programme"):
            cid = prog.attrib.get("channel", "").strip()
            if not cid:
                continue
            start = parse_xmltv_time(prog.attrib.get("start", ""))
            if start is None:
                continue
            stop = parse_xmltv_time(prog.attrib.get("stop", ""))
            if stop is not None:
                if not (start < window_end and stop > window_start):
                    continue
            elif start > window_end:
                continue
            if cid not in local:
                local[cid] = {"name": "", "icon": "", "programs": [], "fileIndex": file_index}
            title = _text(prog, "title")
            if not title:
                continue
            item = {
                "s": start,
                "t": title,
                "d": _text(prog, "desc")[:400],
                "c": _text(prog, "category"),
                "ep": _episode(prog),
                "i": _icon(prog),
            }
            if stop is not None:
                item["e"] = stop
            local[cid]["programs"].append(item)

        for cid, data in local.items():
            if cid not in best or len(data["programs"]) > len(best[cid]["programs"]):
                best[cid] = data

    out_channels: dict[str, dict] = {}
    for cid, data in best.items():
        programs = sorted(data["programs"], key=lambda p: p["s"])
        unknown = sum(1 for p in programs if "e" not in p)
        known = [p["e"] for p in programs if "e" in p]
        last_stop = max(known) if known else None
        end_known = False
        if programs and "e" in programs[-1] and last_stop is not None:
            end_known = last_stop >= window_end
        out_channels[cid] = {
            "name": data["name"],
            "icon": data["icon"],
            "programCount": len(programs),
            "unknownDurationCount": unknown,
            "lastStop": last_stop,
            "endKnown": end_known,
            "programs": programs,
        }

    return {
        "schema": 1,
        "generatedAt": now,
        "windowStart": window_start,
        "windowEnd": window_end,
        "channels": out_channels,
    }

def channel_has_programs(epg: dict, cid: str) -> bool:
    channel = (epg.get("channels") or {}).get(cid)
    return bool(channel and channel.get("programs"))


def channel_unknown_duration(epg: dict, cid: str) -> bool:
    channel = (epg.get("channels") or {}).get(cid)
    return bool(channel and channel.get("unknownDurationCount", 0) > 0)
