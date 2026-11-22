"""Local M3U parser and validators used by the metadata pipeline.

The semantics intentionally mirror source/m3u_parser.brs:
- EXTINF names are the text after the last comma.
- Attributes use double quotes.
- group-title paths are normalized with forward slashes.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field
from typing import Iterable


@dataclass
class Channel:
    kind: str = "ch"
    name: str = ""
    group: str = ""
    url: str = ""
    subs: str = ""
    tvg_id: str = ""
    tvg_name: str = ""
    logo_url: str = ""

    def as_dict(self) -> dict:
        return {
            "kind": self.kind,
            "name": self.name,
            "group": self.group,
            "url": self.url,
            "subs": self.subs,
            "tvgId": self.tvg_id,
            "tvgName": self.tvg_name,
            "logoUrl": self.logo_url,
        }


@dataclass
class Validation:
    ok: bool
    reason: str
    items: list[Channel] = field(default_factory=list)
    truncated: bool = False
    html: bool = False
    invalid_urls: int = 0


def get_attr(line: str, key: str) -> str:
    token = f'{key}="'
    start = line.find(token)
    if start < 0:
        return ""
    start += len(token)
    end = line.find('"', start)
    if end < 0:
        return ""
    return line[start:end]


def norm_path(value: str) -> str:
    value = value.strip().replace("\\", "/").replace(" / ", "/")
    return value.strip("/")


def parse_m3u(text: str) -> list[Channel]:
    out: list[Channel] = []
    if not text:
        return out
    name = group = subs = tvg_id = tvg_name = logo_url = ""
    have = False
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#EXTINF"):
            parts = line.split(",")
            name = parts[-1].strip() if parts else ""
            group = norm_path(get_attr(line, "group-title"))
            subs = get_attr(line, "subtitles")
            tvg_id = get_attr(line, "tvg-id")
            tvg_name = get_attr(line, "tvg-name")
            logo_url = get_attr(line, "tvg-logo")
            have = True
        elif not line.startswith("#"):
            if not have or not name:
                name = line
            out.append(Channel(name=name, group=group, url=line, subs=subs,
                               tvg_id=tvg_id, tvg_name=tvg_name, logo_url=logo_url))
            name = group = subs = tvg_id = tvg_name = logo_url = ""
            have = False
    return out


def url_looks_valid(url: str) -> bool:
    url = url.strip()
    if not url:
        return False
    if "://" in url:
        rest = url.split("://", 1)[1]
        host = rest.split("/", 1)[0].strip()
        return bool(host)
    return url.find(":") > 0


def validate_m3u(text: str) -> Validation:
    if not text:
        return Validation(False, "empty")
    upper = text.upper()
    if "<!DOCTYPE" in upper or "<HTML" in upper:
        return Validation(False, "html", html=True)
    lines = [line.strip() for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n") if line.strip()]
    if not lines:
        return Validation(False, "empty")
    first = lines[0]
    if "#EXTM3U" not in first.upper() or first.upper().find("#EXTM3U") > 3:
        return Validation(False, "missing_extm3u")
    if lines[-1].upper().startswith("#EXTINF"):
        return Validation(False, "truncated", truncated=True)
    items = parse_m3u(text)
    if not items:
        return Validation(False, "no_entries")
    valid = sum(1 for item in items if url_looks_valid(item.url))
    invalid = len(items) - valid
    if valid == 0:
        return Validation(False, "no_valid_urls", items=items, invalid_urls=invalid)
    return Validation(True, "ok", items=items, invalid_urls=invalid)


def normalize_text(text: str) -> str:
    lines = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        line = raw.strip()
        if line.startswith("\ufeff"):
            line = line[1:]
        if line:
            lines.append(line)
    return "\n".join(lines)


def content_hash(text: str) -> str:
    return hashlib.sha256(normalize_text(text).encode("utf-8")).hexdigest()


def duplicate_url_count(items: Iterable[Channel]) -> int:
    counts: dict[str, int] = {}
    for item in items:
        if item.url:
            counts[item.url] = counts.get(item.url, 0) + 1
    return sum(value for value in counts.values() if value > 1)


def normalized_name(value: str) -> str:
    value = value.strip().lower()
    for suffix in [" (1080p)", " (720p)", " (576p)", " (480p)", " (360p)", " (4k)", " fhd", " hd", " sd"]:
        value = value.replace(suffix, "")
    value = value.replace("&", "and").replace("+", "plus").replace("_", " ").replace("-", " ")
    return re.sub(r"\s+", " ", value).strip()
