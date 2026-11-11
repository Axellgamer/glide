#!/usr/bin/env python3
"""Fetch .glide/profile.env from the fork (used at codespace boot).

Keeps an older/resumed codespace in sync with settings saved by another one.
Reads GITHUB_TOKEN and GLIDE_PROFILE_REPO / GLIDE_PROFILE_BRANCH.
"""

from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

API = os.environ.get("GITHUB_API_URL", "https://api.github.com")
PATH = ".glide/profile.env"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: profile_fetch.py <profile-file>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    repo = os.environ.get("GLIDE_PROFILE_REPO", "").strip()
    branch = os.environ.get("GLIDE_PROFILE_BRANCH", "").strip()
    if not token or not repo or not branch:
        return 0
    url = f"{API}/repos/{repo}/contents/{urllib.parse.quote(PATH)}?ref={urllib.parse.quote(branch)}"
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            payload = json.loads(response.read())
    except urllib.error.HTTPError as error:
        if error.code == 404:
            print("missing")
            return 0
        print(f"GET {error.code}", file=sys.stderr)
        return 1
    except OSError as error:
        print(f"GET failed: {error}", file=sys.stderr)
        return 1

    try:
        remote = base64.b64decode(payload.get("content", "")).decode("utf-8")
    except (ValueError, UnicodeDecodeError) as error:
        print(f"bad content: {error}", file=sys.stderr)
        return 1
    try:
        local = open(path, encoding="utf-8").read()
    except OSError:
        local = None
    if local == remote:
        print("unchanged")
        return 0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(remote)
    print("updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
