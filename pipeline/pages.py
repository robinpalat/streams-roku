"""GitHub repository and Pages URL helpers.

The repository is never hardcoded: production configuration resolves it from an
explicit argument, GITHUB_REPOSITORY, or the origin remote.
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path


class PagesConfigError(ValueError):
    pass


def normalize_meta_path(value: str) -> str:
    path = (value or "/real/").strip()
    if not path.startswith("/"):
        path = "/" + path
    if not path.endswith("/"):
        path += "/"
    return path


def parse_repo_slug(value: str) -> str:
    text = (value or "").strip()
    if not text:
        raise PagesConfigError("repository is empty")
    text = text.rstrip("/")
    if text.endswith(".git"):
        text = text[:-4]
    if text.startswith("git@"):
        match = re.match(r"^git@[^:]+:(.+)$", text)
        if not match:
            raise PagesConfigError(f"invalid SSH repository: {value}")
        text = match.group(1)
    elif "://" in text:
        match = re.match(r"^[a-z]+://[^/]+/(.+)$", text, re.IGNORECASE)
        if not match:
            raise PagesConfigError(f"invalid repository URL: {value}")
        text = match.group(1)
    elif ":" in text and "/" in text.split(":", 1)[1]:
        text = text.split(":", 1)[1]
    parts = [p for p in text.split("/") if p]
    if len(parts) != 2:
        raise PagesConfigError(f"repository must be owner/name: {value}")
    owner, repo = parts
    if not re.match(r"^[A-Za-z0-9_.-]+$", owner) or not re.match(r"^[A-Za-z0-9_.-]+$", repo):
        raise PagesConfigError(f"invalid owner/repository: {value}")
    return f"{owner}/{repo}"


def resolve_repo_slug(repo_url: str = "", cwd: Path | None = None) -> str:
    if repo_url:
        return parse_repo_slug(repo_url)
    env_repo = os.environ.get("GITHUB_REPOSITORY", "")
    if env_repo:
        return parse_repo_slug(env_repo)
    try:
        out = subprocess.check_output(
            ["git", "config", "--get", "remote.origin.url"],
            cwd=str(cwd or Path.cwd()), text=True, stderr=subprocess.DEVNULL,
        ).strip()
    except Exception as exc:  # noqa: BLE001
        raise PagesConfigError(
            "cannot resolve repository; pass --repo-url or set GITHUB_REPOSITORY"
        ) from exc
    if not out:
        raise PagesConfigError(
            "cannot resolve repository; pass --repo-url or set GITHUB_REPOSITORY"
        )
    return parse_repo_slug(out)


def pages_base(repo_slug: str, meta_path: str = "/real/") -> str:
    slug = parse_repo_slug(repo_slug)
    owner, repo = slug.split("/", 1)
    path = normalize_meta_path(meta_path).lstrip("/")
    if repo.lower() == f"{owner.lower()}.github.io":
        root = f"https://{owner}.github.io/"
    else:
        root = f"https://{owner}.github.io/{repo}/"
    return root + path


def public_path(repo_slug: str, meta_path: str = "/real/") -> str:
    return "/" + normalize_meta_path(meta_path).lstrip("/")


def site_base(repo_slug: str) -> str:
    slug = parse_repo_slug(repo_slug)
    owner, repo = slug.split("/", 1)
    if repo.lower() == f"{owner.lower()}.github.io":
        return f"https://{owner}.github.io/"
    return f"https://{owner}.github.io/{repo}/"
