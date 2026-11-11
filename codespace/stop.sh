#!/usr/bin/env bash
# Glide Codespace - stop every part of the session.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

SAVE="${1:-}"
glide_ensure_dirs

kill_pidfile() {
  local name="$1" pid_file="$GLIDE_RUN_DIR/$1.pid" pid
  [ -f "$pid_file" ] || return 0
  pid="$(cat "$pid_file" 2>/dev/null)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    local i
    for i in $(seq 1 20); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.25
    done
    kill -KILL "$pid" 2>/dev/null || true
  fi
  rm -f "$pid_file"
}

glide_log "stopping Glide session"

# 1. Minecraft first so it can write its world to disk cleanly.
kill_pidfile minecraft
pkill -u "$(id -u)" -TERM -f "glide_launch.py" >/dev/null 2>&1 || true
pkill -u "$(id -u)" -TERM -f "net.minecraft.client.main.Main" >/dev/null 2>&1 || true
# Give the JVM time to flush the world before anything else is torn down.
for i in $(seq 1 20); do
  pgrep -u "$(id -u)" -f "net.minecraft.client.main.Main" >/dev/null 2>&1 || break
  sleep 0.5
done
pkill -u "$(id -u)" -KILL -f "net.minecraft.client.main.Main" >/dev/null 2>&1 || true

# 2. Streaming stack.
kill_pidfile selkies
if [ -f "$GLIDE_NGINX_DIR/nginx.conf" ] && glide_have nginx; then
  nginx -p "$GLIDE_NGINX_DIR" -c "$GLIDE_NGINX_DIR/nginx.conf" -s quit >/dev/null 2>&1 || true
fi
kill_pidfile console

# 3. Window manager and display.
kill_pidfile dwm
pkill -u "$(id -u)" -x dwm >/dev/null 2>&1 || true
kill_pidfile xvfb
pkill -u "$(id -u)" -f "Xvfb $GLIDE_DISPLAY" >/dev/null 2>&1 || true

# 4. Audio.
pulseaudio --kill >/dev/null 2>&1 || true
rm -f "$GLIDE_RUN_DIR/pulse.done"

if [ "$SAVE" = "--save" ]; then
  glide_state_stage stopped "Session stopped (saving state)"
  bash "$HERE/glide" save >/dev/null 2>&1 || true
fi

glide_state_set STAGE stopped DETAIL "Session stopped" SESSION_STARTED_AT 0
glide_log "stopped"
