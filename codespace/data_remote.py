#!/usr/bin/env python3
"""Push/pull the world/mods/packs archive to the portable store.

Usage: data_remote.py push FILE | pull FILE
Env:   GLIDE_SYNC_URL, GLIDE_SYNC_KEY
"""

from __future__ import annotations

import os
import sys
import urllib.error
import urllib.request

MAX_BYTES = 40 * 1024 * 1024


def endpoint(key: str) -> str:
    base = os.environ.get("GLIDE_SYNC_URL", "").rstrip("/")
    if not base:
        raise SystemExit("missing GLIDE_SYNC_URL")
    return f"{base}/v1/data/{key}"


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in {"push", "pull"}:
        print("usage: data_remote.py push|pull FILE", file=sys.stderr)
        return 2
    action, path = sys.argv[1], sys.argv[2]
    key = os.environ.get("GLIDE_SYNC_KEY", "").strip().lower()
    if not (len(key) == 64 and all(c in "0123456789abcdef" for c in key)):
        print("missing or invalid sync key", file=sys.stderr)
        return 2
    url = endpoint(key)

    if action == "push":
        try:
            body = open(path, "rb").read()
        except OSError as error:
            print(f"cannot read archive: {error}", file=sys.stderr)
            return 1
        if len(body) > MAX_BYTES:
            print("archive too large (40 MB limit)", file=sys.stderr)
            return 1
        request = urllib.request.Request(url, data=body, method="PUT")
        request.add_header("Content-Type", "application/gzip")
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                response.read()
            print("pushed")
            return 0
        except urllib.error.HTTPError as error:
            print(f"push {error.code}", file=sys.stderr)
            return 1
        except OSError as error:
            print(f"push failed: {error}", file=sys.stderr)
            return 1

    request = urllib.request.Request(url, method="GET")
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            remote = response.read()
    except urllib.error.HTTPError as error:
        if error.code == 404:
            print("missing")
            return 3
        print(f"pull {error.code}", file=sys.stderr)
        return 1
    except OSError as error:
        print(f"pull failed: {error}", file=sys.stderr)
        return 1

    try:
        with open(path, "wb") as handle:
            handle.write(remote)
    except OSError as error:
        print(f"cannot write archive: {error}", file=sys.stderr)
        return 1
    print("updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
