#!/usr/bin/env python3
"""Commit .glide/profile.env to the user's fork via the GitHub Contents API.

Called from glide_profile_sync with GITHUB_TOKEN (Codespaces injects it) and
GLIDE_PROFILE_REPO / GLIDE_PROFILE_BRANCH. No third-party dependencies.
"""

from __future__ import annotations

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = os.environ.get("GITHUB_API_URL", "https://api.github.com")
PATH = ".glide/profile.env"


def request(method: str, url: str, token: str, payload: dict | None = None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=20) as response:
        body = response.read()
        return response.status, (json.loads(body) if body else {})


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: profile_sync.py <profile-file>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    repo = os.environ.get("GLIDE_PROFILE_REPO", "").strip()
    branch = os.environ.get("GLIDE_PROFILE_BRANCH", "").strip()
    reason = os.environ.get("GLIDE_PROFILE_REASON", "settings")
    if not token or not repo or not branch:
        print("missing token/repository/branch", file=sys.stderr)
        return 2
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as error:
        print(f"cannot read profile: {error}", file=sys.stderr)
        return 2

    encoded = base64.b64encode(text.encode()).decode()
    url = f"{API}/repos/{repo}/contents/{urllib.parse.quote(PATH)}"

    for attempt in range(2):
        sha = None
        existing = None
        try:
            status, payload = request("GET", f"{url}?ref={urllib.parse.quote(branch)}", token)
            if status == 200:
                sha = payload.get("sha")
                try:
                    existing = base64.b64decode(payload.get("content", "")).decode("utf-8")
                except (ValueError, UnicodeDecodeError):
                    existing = None
        except urllib.error.HTTPError as error:
            if error.code != 404:
                print(f"GET {error.code}: {error.read()[:200]!r}", file=sys.stderr)
                return 1
        if existing == text:
            print("profile unchanged")
            return 0
        body = {
            "message": f"Glide profile: {reason}",
            "content": encoded,
            "branch": branch,
        }
        if sha:
            body["sha"] = sha
        try:
            status, payload = request("PUT", url, token, body)
            if status in (200, 201):
                print(f"committed {payload.get('commit', {}).get('sha', '')[:7]}")
                return 0
        except urllib.error.HTTPError as error:
            detail = error.read()[:300]
            if error.code == 409 and attempt == 0:
                time.sleep(0.6)
                continue
            print(f"PUT {error.code}: {detail!r}", file=sys.stderr)
            return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
