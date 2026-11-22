"""Build a compact catalog from an M3U and optional iptv-org snapshots."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable

from .m3u import Channel

IMAGE_FORMATS = {"PNG", "JPEG", "JPG", "WEBP"}


def load_json(path: str | Path | None, default):
    if not path:
        return default
    p = Path(path)
    if not p.exists():
        return default
    with p.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def _read_list(path: str | Path | None) -> list:
    value = load_json(path, [])
    return value if isinstance(value, list) else []


class CatalogBuilder:
    def __init__(self, channels_path: str | Path | None = None,
                 feeds_path: str | Path | None = None,
                 logos_path: str | Path | None = None,
                 aliases_path: str | Path | None = None):
        self.channels = {c.get("id"): c for c in _read_list(channels_path) if c.get("id")}
        self.feeds = {}
        for feed in _read_list(feeds_path):
            cid = feed.get("channel")
            fid = feed.get("id")
            if cid and fid:
                self.feeds[f"{cid}@{fid}"] = feed
        self.logo_by_key: dict[str, list[dict]] = {}
        for logo in _read_list(logos_path):
            cid = logo.get("channel")
            if not cid:
                continue
            key = f"{cid}@{logo.get('feed')}" if logo.get("feed") else cid
            self.logo_by_key.setdefault(key, []).append(logo)
        aliases = load_json(aliases_path, {})
        self.aliases = aliases.get("logos", {}) if isinstance(aliases, dict) else {}

    def _logo(self, item: Channel) -> str:
        if item.logo_url:
            return item.logo_url
        cid, feed = split_tvg_id(item.tvg_id)
        keys = []
        if feed:
            keys.append(f"{cid}@{feed}")
        keys.append(cid)
        for key in keys:
            for logo in self._sorted_logos(key):
                url = logo.get("url")
                fmt = (logo.get("format") or "").upper()
                if url and (not fmt or fmt in IMAGE_FORMATS):
                    return url
        alias = self.aliases.get(item.tvg_id) or self.aliases.get(cid)
        if alias:
            return alias
        return ""

    def _sorted_logos(self, key: str) -> list[dict]:
        return sorted(
            self.logo_by_key.get(key, []),
            key=lambda l: (not bool(l.get("in_use")), (l.get("format") or "").upper() not in IMAGE_FORMATS,
                           -(int(l.get("width") or 0) * int(l.get("height") or 0))),
        )

    def build(self, source_id: str, items: Iterable[Channel], epg: dict | None = None,
              generated_at: int = 0) -> dict:
        channels: dict[str, dict] = {}
        stream_map: dict[str, str] = {}
        epg_channels = (epg or {}).get("channels", {}) if epg else {}
        for item in items:
            if not item.tvg_id:
                continue
            cid, feed = split_tvg_id(item.tvg_id)
            api_channel = self.channels.get(cid, {})
            api_feed = self.feeds.get(item.tvg_id, {})
            stream_map[item.url] = item.tvg_id
            if item.tvg_id in channels:
                continue
            languages = api_feed.get("languages") or []
            timezones = api_feed.get("timezones") or []
            epg_channel = epg_channels.get(item.tvg_id)
            channels[item.tvg_id] = {
                "channel": cid,
                "feed": feed,
                "name": item.name,
                "apiName": api_channel.get("name", ""),
                "altNames": api_channel.get("alt_names", []),
                "country": api_channel.get("country", ""),
                "lang": languages[0] if languages else "",
                "timezone": timezones[0] if timezones else "",
                "logo": self._logo(item),
                "epgId": item.tvg_id,
                "hasEpg": bool(epg_channel and epg_channel.get("programs")),
                "match": "tvg-id" if api_channel else "m3u",
                "confidence": 1.0 if api_channel else 0.8,
            }
        return {
            "schema": 1,
            "sourceId": source_id,
            "generatedAt": generated_at,
            "logoBase": "",
            "placeholder": "pkg:/images/logo_placeholder.png",
            "channels": channels,
            "streamMap": stream_map,
        }


def split_tvg_id(tvg_id: str) -> tuple[str, str]:
    if not tvg_id:
        return "", ""
    if "@" in tvg_id:
        return tuple(tvg_id.split("@", 1))  # type: ignore[return-value]
    return tvg_id, ""
