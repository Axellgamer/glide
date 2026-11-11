#!/usr/bin/env bash
# Glide Codespace - session boot.
#
# Starts, in order: virtual display -> audio -> Selkies -> nginx proxy ->
# Minecraft. Every step is idempotent, so running it again only starts whatever
# is missing.
#
#   bash codespace/boot.sh            # everything
#   bash codespace/boot.sh --stream   # display/audio/stream/proxy only
#   bash codespace/boot.sh --game     # (re)launch Minecraft only
#   bash codespace/boot.sh --detach   # return immediately (devcontainer)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

MODE="all"
DETACH=0
for arg in "$@"; do
  case "$arg" in
    --all) MODE="all" ;;
    --stream) MODE="stream" ;;
    --game) MODE="game" ;;
    --detach) DETACH=1 ;;
    --force) FORCE=1 ;;
    -h | --help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) ;;
  esac
done
FORCE="${FORCE:-0}"

glide_ensure_dirs
if declare -F glide_profile_pull >/dev/null 2>&1; then
  glide_profile_pull
fi
glide_load_env

BOOT_LOG="$GLIDE_LOG_DIR/boot.log"
if [ "$DETACH" = "1" ] && [ -z "${GLIDE_BOOT_ACTIVE:-}" ]; then
  GLIDE_BOOT_ACTIVE=1 setsid nohup bash "$HERE/boot.sh" $([ "$MODE" = all ] || echo "--$MODE") \
    >/dev/null 2>&1 </dev/null &
  glide_log "boot started in the background (log: $BOOT_LOG)"
  exit 0
fi

printf '\n===== glide boot %s (%s) =====\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$MODE" >>"$BOOT_LOG"
exec > >(tee -a "$BOOT_LOG") 2>&1

# One boot at a time.
exec 9>"$GLIDE_HOME/boot.lock"
if ! flock -n 9; then
  glide_log "another boot is already running; nothing to do"
  exit 0
fi

if [ ! -f "$GLIDE_HOME/setup.stamp" ]; then
  glide_die "setup has not run yet - run: bash codespace/setup.sh"
fi

export DISPLAY="$GLIDE_DISPLAY"
export XDG_RUNTIME_DIR="$GLIDE_XDG_RUNTIME_DIR"
export PULSE_RUNTIME_PATH="$GLIDE_PULSE_RUNTIME_PATH"
export PULSE_SERVER="$GLIDE_PULSE_SERVER"
export PULSE_SINK="$GLIDE_PULSE_SINK"

die_tail() {
  glide_log "$1"
  [ -n "${2:-}" ] && [ -f "$2" ] && tail -n 40 "$2"
  glide_die "$1"
}

# ----------------------------------------------------------------- display ---
start_display() {
  if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    glide_log "display $DISPLAY already up"
    return 0
  fi
  glide_state_stage display "starting virtual display ${GLIDE_RES_WIDTH}x${GLIDE_RES_HEIGHT}"
  rm -f "/tmp/.X11-unix/X${DISPLAY#:}" 2>/dev/null || true
  setsid nohup Xvfb "$DISPLAY" -screen 0 "${GLIDE_RES_WIDTH}x${GLIDE_RES_HEIGHT}x24" \
    -ac -nolisten tcp +extension GLX +extension RANDR \
    >"$GLIDE_LOG_DIR/xvfb.log" 2>&1 </dev/null &
  echo $! >"$GLIDE_RUN_DIR/xvfb.pid"

  local i
  for i in $(seq 1 40); do
    xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
    sleep 0.5
  done
  xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 \
    || die_tail "Xvfb did not come up on $DISPLAY" "$GLIDE_LOG_DIR/xvfb.log"
  xsetroot -display "$DISPLAY" -solid "#0a0c10" >/dev/null 2>&1 || true
  glide_log "display ready: ${GLIDE_RES_WIDTH}x${GLIDE_RES_HEIGHT} on $DISPLAY"

  if glide_have dwm && ! pgrep -u "$(id -u)" -x dwm >/dev/null 2>&1; then
    DISPLAY="$DISPLAY" setsid nohup dwm >"$GLIDE_LOG_DIR/dwm.log" 2>&1 </dev/null &
    echo $! >"$GLIDE_RUN_DIR/dwm.pid"
    sleep 0.5
    glide_log "window manager: dwm"
  else
    glide_log "window manager: none"
  fi
}

# ------------------------------------------------------------------- audio ---
start_audio() {
  if [ "$GLIDE_AUDIO" != "true" ]; then
    glide_state_set AUDIO_READY false
    glide_log "audio disabled in session.env"
    return 0
  fi
  glide_state_stage audio "starting pulseaudio"
  if [ -f "$GLIDE_RUN_DIR/pulse.done" ] && pactl info >/dev/null 2>&1; then
    glide_log "audio already up"
    return 0
  fi
  pulseaudio --kill >/dev/null 2>&1 || true
  rm -f "$PULSE_RUNTIME_PATH/native"
  mkdir -p "$PULSE_RUNTIME_PATH"
  # Start the daemon without PULSE_SERVER exported, otherwise pulseaudio thinks
  # a server already exists and refuses to spawn.
  env -u PULSE_SERVER pulseaudio --start --daemonize=yes --system=false \
    --exit-idle-time=-1 --log-target="file:$GLIDE_LOG_DIR/pulseaudio.log" >/dev/null 2>&1 || true

  local i
  for i in $(seq 1 40); do
    [ -S "$PULSE_RUNTIME_PATH/native" ] && break
    sleep 0.5
  done
  if [ ! -S "$PULSE_RUNTIME_PATH/native" ]; then
    glide_log "pulseaudio did not start - continuing without audio"
    glide_state_set AUDIO_READY false
    return 0
  fi
  pactl load-module module-virtual-sink sink_name="$PULSE_SINK" \
    sink_properties=device.description=GlideGame >/dev/null 2>&1 || true
  pactl set-default-sink "$PULSE_SINK" >/dev/null 2>&1 || true
  pactl set-default-source "$PULSE_SINK.monitor" >/dev/null 2>&1 || true
  pactl set-sink-volume "$PULSE_SINK" 100% >/dev/null 2>&1 || true
  pactl suspend-sink "$PULSE_SINK" false >/dev/null 2>&1 || true
  touch "$GLIDE_RUN_DIR/pulse.done"
  glide_state_set AUDIO_READY true
  glide_log "audio ready: $PULSE_SINK"
}

# ------------------------------------------------------------------ selkies ---
start_stream() {
  local bin
  bin="$(glide_selkies_bin)"
  [ -n "$bin" ] || glide_die "selkies is not installed - run: bash codespace/setup.sh"
  if glide_pid_alive "$GLIDE_RUN_DIR/selkies.pid" &&
    curl -fsS -u "glide:$GLIDE_SELKIES_PASSWORD" --max-time 2 \
      "http://127.0.0.1:$GLIDE_SELKIES_PORT/" >/dev/null 2>&1; then
    glide_log "stream already up on :$GLIDE_SELKIES_PORT"
    return 0
  fi
  glide_state_stage stream "starting Selkies on :$GLIDE_SELKIES_PORT"

  # One value per encoder setting locks the choice in the dashboard.
  export SELKIES_PORT="$GLIDE_SELKIES_PORT"
  export SELKIES_ENABLE_HTTPS=false
  export SELKIES_ENABLE_BASIC_AUTH=true
  export SELKIES_BASIC_AUTH_USER=glide
  export SELKIES_BASIC_AUTH_PASSWORD="$GLIDE_SELKIES_PASSWORD"
  export SELKIES_ENCODER="$GLIDE_ENCODER"
  export SELKIES_ENABLE_RESIZE=false
  export SELKIES_FRAMERATE="$GLIDE_FPS"
  export SELKIES_VIDEO_BITRATE="$GLIDE_BITRATE"
  export SELKIES_AUDIO_ENABLED="$GLIDE_AUDIO"
  # The dashboard is embedded in Glide's own UI, so it has to allow framing.
  export SELKIES_ALLOWED_ORIGINS="*"
  export SELKIES_FRAME_ANCESTORS="*"
  export SELKIES_UI_TITLE="Glide"
  export SELKIES_UI_SHOW_LOGO=false
  export SELKIES_UI_SHOW_SIDEBAR="$GLIDE_DASHBOARD"
  export DISPLAY XDG_RUNTIME_DIR PULSE_RUNTIME_PATH PULSE_SERVER

  setsid nohup "$bin" --port="$GLIDE_SELKIES_PORT" --enable-https=false \
    --encoder="$GLIDE_ENCODER" --enable-resize=false \
    --basic-auth-user=glide --basic-auth-password="$GLIDE_SELKIES_PASSWORD" \
    >"$GLIDE_LOG_DIR/selkies.log" 2>&1 </dev/null &
  echo $! >"$GLIDE_RUN_DIR/selkies.pid"

  local i
  for i in $(seq 1 90); do
    if curl -fsS -u "glide:$GLIDE_SELKIES_PASSWORD" --max-time 2 \
      "http://127.0.0.1:$GLIDE_SELKIES_PORT/" >/dev/null 2>&1; then
      glide_log "stream ready on 127.0.0.1:$GLIDE_SELKIES_PORT"
      glide_state_set STREAM_READY true
      return 0
    fi
    if ! kill -0 "$(cat "$GLIDE_RUN_DIR/selkies.pid" 2>/dev/null)" 2>/dev/null; then
      die_tail "Selkies exited during startup" "$GLIDE_LOG_DIR/selkies.log"
    fi
    sleep 1
  done
  die_tail "Selkies did not answer on :$GLIDE_SELKIES_PORT" "$GLIDE_LOG_DIR/selkies.log"
}

# ------------------------------------------------------------------- proxy ---
start_proxy() {
  if glide_port_open "$GLIDE_PROXY_PORT" "/"; then
    glide_log "proxy already up on :$GLIDE_PROXY_PORT"
    return 0
  fi
  glide_state_stage proxy "starting nginx on :$GLIDE_PROXY_PORT"
  glide_have nginx || glide_die "nginx is missing - run: bash codespace/setup.sh"
  local auth
  auth="$(printf 'glide:%s' "$GLIDE_SELKIES_PASSWORD" | base64 | tr -d '\n')"
  mkdir -p "$GLIDE_NGINX_DIR/tmp" "$GLIDE_NGINX_DIR/logs"
  GLIDE_NGINX_HOME="$GLIDE_NGINX_DIR" \
    GLIDE_AUTH_B64="$auth" \
    GLIDE_PROXY_PORT="$GLIDE_PROXY_PORT" \
    GLIDE_SELKIES_PORT="$GLIDE_SELKIES_PORT" \
    python3 - "$HERE/nginx.conf.tpl" "$GLIDE_NGINX_DIR/nginx.conf" <<'PY'
import os
import pathlib
import sys

template = pathlib.Path(sys.argv[1]).read_text()
values = {
    "NGINX_HOME": os.environ["GLIDE_NGINX_HOME"],
    "AUTH_B64": os.environ["GLIDE_AUTH_B64"],
    "PROXY_PORT": os.environ["GLIDE_PROXY_PORT"],
    "SELKIES_PORT": os.environ["GLIDE_SELKIES_PORT"],
}
for key, value in values.items():
    template = template.replace("{{" + key + "}}", value)
pathlib.Path(sys.argv[2]).write_text(template)
PY

  nginx -t -p "$GLIDE_NGINX_DIR" -c "$GLIDE_NGINX_DIR/nginx.conf" >/dev/null 2>&1 \
    || die_tail "nginx config is invalid" "$GLIDE_NGINX_DIR/logs/error.log"
  nginx -p "$GLIDE_NGINX_DIR" -c "$GLIDE_NGINX_DIR/nginx.conf"
  local i
  for i in $(seq 1 30); do
    glide_port_open "$GLIDE_PROXY_PORT" "/healthz" && break
    sleep 0.5
  done
  glide_port_open "$GLIDE_PROXY_PORT" "/healthz" \
    || die_tail "proxy did not answer on :$GLIDE_PROXY_PORT" "$GLIDE_NGINX_DIR/logs/error.log"
  glide_log "proxy ready on :$GLIDE_PROXY_PORT -> :$GLIDE_SELKIES_PORT"
}

# -------------------------------------------------------------------- game ---
sync_assets() {
  local version="$GLIDE_MINECRAFT_VERSION" loader="$GLIDE_MINECRAFT_LOADER"
  local mods_src="$GLIDE_REPO_CLIENT/mods/$version/$loader"
  local packs_src="$GLIDE_REPO_CLIENT/$version/resourcepacks"
  local datapacks_src="$GLIDE_REPO_CLIENT/$version/datapacks/$loader"
  local worlds_src="$GLIDE_REPO_CLIENT/$version/worlds"
  local settings_src="$GLIDE_REPO_CLIENT/$version/settings/$loader"
  local shaders_src="$GLIDE_REPO_CLIENT/Shaders"

  mkdir -p "$GLIDE_MC/mods" "$GLIDE_MC/resourcepacks" "$GLIDE_MC/shaderpacks" \
    "$GLIDE_MC/saves" "$GLIDE_MC/datapacks"

  # Mods are fully managed by the repo, so clear stale versions first.
  find "$GLIDE_MC/mods" -mindepth 1 -maxdepth 1 -type f -name '*.jar' -delete 2>/dev/null || true
  if [ -d "$mods_src" ]; then
    find "$mods_src" -maxdepth 1 -type f \( -name '*.jar' -o -name '*.zip' \) \
      -exec cp -f {} "$GLIDE_MC/mods/" \; 2>/dev/null || true
  fi
  if [ -d "$packs_src" ]; then
    cp -a "$packs_src/." "$GLIDE_MC/resourcepacks/" 2>/dev/null || true
  fi
  if [ -d "$datapacks_src" ]; then
    cp -a "$datapacks_src/." "$GLIDE_MC/datapacks/" 2>/dev/null || true
  fi
  if [ -d "$worlds_src" ]; then
    cp -a "$worlds_src/." "$GLIDE_MC/saves/" 2>/dev/null || true
  fi
  if [ -d "$settings_src" ]; then
    cp -a "$settings_src/." "$GLIDE_MC/" 2>/dev/null || true
  fi
  if [ -d "$shaders_src" ]; then
    find "$shaders_src" -maxdepth 1 -type f -name '*.zip' \
      -exec cp -f {} "$GLIDE_MC/shaderpacks/" \; 2>/dev/null || true
  fi
}

start_game() {
  local version="$GLIDE_MINECRAFT_VERSION"
  local launcher="$GLIDE_REPO_CLIENT/scripts/glide_launch.py"
  [ -f "$launcher" ] || glide_die "missing launcher: $launcher"
  xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || start_display
  glide_state_stage game-booting "syncing mods, packs and worlds"
  sync_assets

  # Stop the previous Minecraft first.
  local was_running=0
  if glide_pid_alive "$GLIDE_RUN_DIR/minecraft.pid"; then
    was_running=1
    kill -TERM "$(cat "$GLIDE_RUN_DIR/minecraft.pid")" >/dev/null 2>&1 || true
    sleep 2
  fi
  pkill -u "$(id -u)" -TERM -f "glide_launch.py" >/dev/null 2>&1 || true
  pkill -u "$(id -u)" -TERM -f "net.minecraft.client.main.Main" >/dev/null 2>&1 || true
  local i
  for i in $(seq 1 20); do
    pgrep -u "$(id -u)" -f "net.minecraft.client.main.Main" >/dev/null 2>&1 || break
    sleep 0.5
  done
  pkill -u "$(id -u)" -KILL -f "net.minecraft.client.main.Main" >/dev/null 2>&1 || true

  # Save the options of the session we just stopped, then apply the latest
  # portable settings before launching. Fresh codespaces pull, restarts
  # push-then-pull (same content).
  if [ "$was_running" = "1" ] && declare -F glide_game_push >/dev/null 2>&1; then
    glide_game_push
  fi
  if declare -F glide_game_pull >/dev/null 2>&1; then
    glide_game_pull || true
  fi

  # Minecraft 1.17 was the first version that needed a newer-than-8 JVM.
  local java_home="$GLIDE_JRE/21" minor
  minor="$(printf '%s' "$version" | awk -F. '{print $2 + 0}')"
  if [ "$minor" -lt 17 ]; then
    java_home="$GLIDE_JRE/8"
  fi
  [ -x "$java_home/bin/java" ] || glide_die "missing Java runtime at $java_home"
  export JAVA_HOME="$java_home"
  export PATH="$java_home/bin:$PATH"

  export GLIDE_MINECRAFT_VERSION="$version"
  export GLIDE_MINECRAFT_LOADER="$GLIDE_MINECRAFT_LOADER"
  export GLIDE_MINECRAFT_XMX="$GLIDE_MINECRAFT_XMX"
  export GLIDE_MINECRAFT_DIR="$GLIDE_MC"
  export GLIDE_RESOLUTION_PRESET=custom
  export GLIDE_RENDER_WIDTH="$GLIDE_RES_WIDTH"
  export GLIDE_RENDER_HEIGHT="$GLIDE_RES_HEIGHT"
  export GLIDE_AUTH_MODE="$GLIDE_AUTH_MODE"
  export GLIDE_OFFLINE_USERNAME="$GLIDE_OFFLINE_USERNAME"
  export GLIDE_MAX_RESTARTS="$GLIDE_MAX_RESTARTS"
  export GLIDE_RENDERER="$GLIDE_RENDERER"
  export DISPLAY XDG_RUNTIME_DIR PULSE_RUNTIME_PATH PULSE_SERVER PULSE_SINK
  export PULSE_SOURCE="$PULSE_SINK.monitor"
  export PULSE_LATENCY_MSEC=60
  export PULSE_SUSPEND_ON_IDLE=no
  export SDL_AUDIODRIVER=pulseaudio
  export AUDIODRIVER=pulseaudio
  export ALSOFT_DRIVERS=pulse
  export __GL_MaxFramesAllowed=1
  export vblank_mode=0
  export GLIDE_LOW_LATENCY=1
  export GLIDE_GPU_MODE=auto
  export GLIDE_CAPTURE_MODE=auto

  local agent="$GLIDE_REPO_CLIENT/glide-runtime-agent/build/glide-runtime-agent.jar"
  [ -f "$agent" ] && export GLIDE_RUNTIME_AGENT="$agent" || export GLIDE_RUNTIME_AGENT=""

  local bridge="$GLIDE_REPO_CLIENT/target/release/libglide_gl_bridge.so"
  if [ "${GLIDE_USE_BRIDGE:-0}" = "1" ] && [ -f "$bridge" ]; then
    export LD_PRELOAD="$bridge"
    export GLIDE_VULKAN_BRIDGE=0
    glide_log "GL bridge preloaded"
  else
    export LD_PRELOAD=""
  fi

  setsid nohup "$GLIDE_VENV/bin/python" "$launcher" \
    >"$GLIDE_LOG_DIR/minecraft.log" 2>&1 </dev/null &
  echo $! >"$GLIDE_RUN_DIR/minecraft.pid"

  sleep 2
  if ! kill -0 "$(cat "$GLIDE_RUN_DIR/minecraft.pid")" 2>/dev/null; then
    die_tail "Minecraft launcher exited immediately" "$GLIDE_LOG_DIR/minecraft.log"
  fi
  glide_state_set STAGE game-booting DETAIL "Minecraft ${version} (${GLIDE_MINECRAFT_LOADER}) is booting" \
    PIDS_MC "$(cat "$GLIDE_RUN_DIR/minecraft.pid")"
  glide_log "Minecraft launcher started (log: $GLIDE_LOG_DIR/minecraft.log)"
}

# --------------------------------------------------------------------- run ---
case "$MODE" in
  all | stream)
    glide_state_set SESSION_STARTED_AT "$(date +%s)" LAST_ERROR ""
    ;;
esac

case "$MODE" in
  all)
    start_display
    start_audio
    start_stream
    start_proxy
    start_game
    ;;
  stream)
    start_display
    start_audio
    start_stream
    start_proxy
    glide_state_set STAGE stream-ready DETAIL "Stream is live, waiting for Minecraft"
    ;;
  game)
    start_game
    ;;
esac

glide_log "boot finished - open: $(glide_public_url)"
