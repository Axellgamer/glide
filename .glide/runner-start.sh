#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p "$HOME/.glide/logs" "$HOME/.glide/run"
if [ -f "$HOME/.glide/run/runner.pid" ] && kill -0 "$(cat "$HOME/.glide/run/runner.pid")" 2>/dev/null; then exit 0; fi
if ! python3 -c 'import pyte' 2>/dev/null || ! command -v gh >/dev/null || ! command -v openssl >/dev/null; then
  sudo apt-get update -qq
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-pyte openssl gh
fi
nohup python3 -u .glide/runner.py >>"$HOME/.glide/logs/runner.log" 2>&1 </dev/null &
echo $! >"$HOME/.glide/run/runner.pid"
