#!/usr/bin/env bash
# Glide Codespace - shared helpers, paths and defaults.
# Sourced by setup.sh, boot.sh, stop.sh and the `glide` CLI.

set -o pipefail

GLIDE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GLIDE_ROOT

export GLIDE_HOME="${GLIDE_HOME:-$HOME/.glide}"
export GLIDE_LOG_DIR="$GLIDE_HOME/logs"
export GLIDE_RUN_DIR="$GLIDE_HOME/run"
export GLIDE_MC="${GLIDE_MC:-$GLIDE_HOME/minecraft}"
export GLIDE_VENV="$GLIDE_HOME/venv"
export GLIDE_JRE="$GLIDE_HOME/jre"
export GLIDE_NGINX_DIR="$GLIDE_HOME/nginx"
export GLIDE_SESSION_ENV="$GLIDE_HOME/session.env"
export GLIDE_STATE_FILE="$GLIDE_HOME/state.env"
export GLIDE_REPO_CLIENT="$GLIDE_ROOT/Client"

# Ports. 6080 stays private; open it from the signed-in github.dev session.
export GLIDE_PROXY_PORT="${GLIDE_PROXY_PORT:-6080}"
export GLIDE_SELKIES_PORT="${GLIDE_SELKIES_PORT:-8080}"

# Display / audio.
export GLIDE_DISPLAY="${GLIDE_DISPLAY:-:99}"
export GLIDE_XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/glide-runtime}"
export GLIDE_PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-$GLIDE_XDG_RUNTIME_DIR/pulse}"
export GLIDE_PULSE_SERVER="${PULSE_SERVER:-unix:$GLIDE_PULSE_RUNTIME_PATH/native}"
export GLIDE_PULSE_SINK="${PULSE_SINK:-glide_game_sink}"

# Session env defaults. Written once to ~/.glide/session.env, then user owned.
: "${GLIDE_DEFAULTS_VERSION:=1.21.5}"
: "${GLIDE_DEFAULTS_LOADER:=fabric}"
: "${GLIDE_DEFAULTS_XMX:=4G}"
: "${GLIDE_DEFAULTS_RESOLUTION:=1280x720}"
: "${GLIDE_DEFAULTS_FPS:=60}"
: "${GLIDE_DEFAULTS_BITRATE:=6000}"
: "${GLIDE_DEFAULTS_ENCODER:=h264enc}"
: "${GLIDE_DEFAULTS_AUTH_MODE:=offline}"
: "${GLIDE_DEFAULTS_USERNAME:=GlidePlayer}"

glide_ensure_dirs() {
  mkdir -p "$GLIDE_HOME" "$GLIDE_LOG_DIR" "$GLIDE_RUN_DIR" "$GLIDE_MC" \
    "$GLIDE_NGINX_DIR/tmp" "$GLIDE_NGINX_DIR/logs" "$GLIDE_XDG_RUNTIME_DIR" \
    "$GLIDE_PULSE_RUNTIME_PATH"
  chmod 700 "$GLIDE_XDG_RUNTIME_DIR" 2>/dev/null || true
}

glide_random() {
  # $1 = number of bytes, printed as a URL safe token.
  python3 -c 'import secrets,sys; print(secrets.token_urlsafe(int(sys.argv[1])))' "${1:-18}" \
    2>/dev/null || head -c "${1:-18}" /dev/urandom | base64 | tr -d '/+=' | cut -c1-24
}

glide_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

glide_have() { command -v "$1" >/dev/null 2>&1; }

glide_port_open() {
  # $1 = port, $2 = optional path (checked with curl)
  local port="$1" path="${2:-/}"
  if glide_have curl; then
    curl -fsS --max-time 2 "http://127.0.0.1:${port}${path}" >/dev/null 2>&1
  else
    (echo >"/dev/tcp/127.0.0.1/${port}") >/dev/null 2>&1
  fi
}

glide_write_defaults() {
  glide_ensure_dirs
  if [ -f "$GLIDE_SESSION_ENV" ]; then
    return 0
  fi
  local resolution="$GLIDE_DEFAULTS_RESOLUTION"
  cat >"$GLIDE_SESSION_ENV" <<EOF
# Glide Codespace session config. Edit with: glide env
# Everything here is read by boot.sh every time a session starts.

# --- Minecraft ---------------------------------------------------------------
GLIDE_MINECRAFT_VERSION=$GLIDE_DEFAULTS_VERSION
GLIDE_MINECRAFT_LOADER=$GLIDE_DEFAULTS_LOADER
GLIDE_MINECRAFT_XMX=$GLIDE_DEFAULTS_XMX
GLIDE_AUTH_MODE=$GLIDE_DEFAULTS_AUTH_MODE
GLIDE_OFFLINE_USERNAME=$GLIDE_DEFAULTS_USERNAME
GLIDE_SKIN_MODEL=classic
GLIDE_MAX_RESTARTS=3

# --- Display (restart the session to apply a new resolution) ------------------
GLIDE_RESOLUTION=$resolution
GLIDE_RENDERER=auto

# --- Stream ------------------------------------------------------------------
GLIDE_FPS=$GLIDE_DEFAULTS_FPS
GLIDE_BITRATE=$GLIDE_DEFAULTS_BITRATE
GLIDE_ENCODER=$GLIDE_DEFAULTS_ENCODER
GLIDE_AUDIO=true
# true = show the Selkies dashboard sidebar inside the stream, false = clean video
GLIDE_DASHBOARD=true

# --- Generated, do not edit --------------------------------------------------
GLIDE_SELKIES_PASSWORD=$(glide_random 18)
EOF
  chmod 600 "$GLIDE_SESSION_ENV"
}

glide_load_env() {
  glide_ensure_dirs
  glide_write_defaults
  # The repository copy of .glide/profile.env is the durable store: it is
  # applied before the local session env, so a new codespace starts with the
  # user's last settings. Local-only keys (Selkies password) are preserved.
  if declare -F glide_profile_import >/dev/null 2>&1; then
    glide_profile_import
  fi
  # shellcheck disable=SC1090
  . "$GLIDE_SESSION_ENV"
  : "${GLIDE_MINECRAFT_VERSION:=$GLIDE_DEFAULTS_VERSION}"
  : "${GLIDE_MINECRAFT_LOADER:=$GLIDE_DEFAULTS_LOADER}"
  : "${GLIDE_MINECRAFT_XMX:=$GLIDE_DEFAULTS_XMX}"
  : "${GLIDE_RESOLUTION:=$GLIDE_DEFAULTS_RESOLUTION}"
  : "${GLIDE_FPS:=$GLIDE_DEFAULTS_FPS}"
  : "${GLIDE_BITRATE:=$GLIDE_DEFAULTS_BITRATE}"
  : "${GLIDE_ENCODER:=$GLIDE_DEFAULTS_ENCODER}"
  : "${GLIDE_AUDIO:=true}"
  : "${GLIDE_DASHBOARD:=true}"
  : "${GLIDE_AUTH_MODE:=offline}"
  : "${GLIDE_OFFLINE_USERNAME:=GlidePlayer}"
  : "${GLIDE_MAX_RESTARTS:=3}"
  : "${GLIDE_RENDERER:=auto}"
  : "${GLIDE_SKIN_MODEL:=classic}"
  : "${GLIDE_MICROSOFT_CLIENT_ID:=}"
  if [ -z "${GLIDE_SELKIES_PASSWORD:-}" ]; then
    GLIDE_SELKIES_PASSWORD="$(glide_random 18)"
    echo "GLIDE_SELKIES_PASSWORD=$GLIDE_SELKIES_PASSWORD" >>"$GLIDE_SESSION_ENV"
  fi
  export GLIDE_MINECRAFT_VERSION GLIDE_MINECRAFT_LOADER GLIDE_MINECRAFT_XMX
  export GLIDE_RESOLUTION GLIDE_FPS GLIDE_BITRATE GLIDE_ENCODER GLIDE_AUDIO
  export GLIDE_DASHBOARD GLIDE_AUTH_MODE GLIDE_OFFLINE_USERNAME
  export GLIDE_MAX_RESTARTS GLIDE_RENDERER GLIDE_SELKIES_PASSWORD
  export GLIDE_SKIN_MODEL GLIDE_MICROSOFT_CLIENT_ID
  if ! printf '%s' "$GLIDE_RESOLUTION" | grep -Eq '^[0-9]{2,5}x[0-9]{2,5}$'; then
    GLIDE_RESOLUTION="$GLIDE_DEFAULTS_RESOLUTION"
  fi
  GLIDE_RES_WIDTH="${GLIDE_RESOLUTION%%x*}"
  GLIDE_RES_HEIGHT="${GLIDE_RESOLUTION##*x}"
  export GLIDE_RES_WIDTH GLIDE_RES_HEIGHT
}

glide_env_set() {
  # glide_env_set KEY VALUE  (rewrites in place, keeps the file tidy)
  local key="$1" value="$2" tmp="$GLIDE_SESSION_ENV.tmp"
  if grep -q "^${key}=" "$GLIDE_SESSION_ENV" 2>/dev/null; then
    awk -v k="$key" -v v="$value" 'BEGIN{FS=OFS="="} $1==k{print k"="v; next} {print}' \
      "$GLIDE_SESSION_ENV" >"$tmp" && mv "$tmp" "$GLIDE_SESSION_ENV"
  else
    printf '%s=%s\n' "$key" "$value" >>"$GLIDE_SESSION_ENV"
  fi
}

# --- state file --------------------------------------------------------------
# A tiny key=value file read by the CLI and the menu. Values are single line.
glide_state_set() {
  # glide_state_set KEY VALUE [KEY VALUE ...]
  local tmp="$GLIDE_STATE_FILE.tmp" key value
  cp -f "$GLIDE_STATE_FILE" "$tmp" 2>/dev/null || : >"$tmp"
  while [ "$#" -ge 2 ]; do
    key="$1"
    value="$(printf '%s' "$2" | tr '\n' ' ')"
    shift 2
    grep -v "^${key}=" "$tmp" >"$tmp.next" 2>/dev/null || : >"$tmp.next"
    printf '%s=%s\n' "$key" "$value" >>"$tmp.next"
    mv "$tmp.next" "$tmp"
  done
  grep -v '^UPDATED_AT=' "$tmp" >"$tmp.next" 2>/dev/null || : >"$tmp.next"
  printf 'UPDATED_AT=%s\n' "$(date +%s)" >>"$tmp.next"
  mv "$tmp.next" "$GLIDE_STATE_FILE"
}

glide_state_stage() {
  glide_state_set STAGE "$1" DETAIL "${2:-}"
}

glide_log() {
  printf '[glide] %s\n' "$*"
}

glide_die() {
  glide_log "ERROR: $*" >&2
  glide_state_stage error "$*"
  exit 1
}

glide_pid_alive() {
  [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null
}

glide_codespace_name() {
  if [ -n "${CODESPACE_NAME:-}" ]; then
    printf '%s' "$CODESPACE_NAME"
  elif [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
    printf '%s' "${CODESPACE_NAME:-}"
  fi
}

glide_public_url() {
  local name url
  name="$(glide_codespace_name)"
  if [ -n "$name" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
    url="https://${name}-${GLIDE_PROXY_PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  elif [ -n "$name" ]; then
    url="https://${name}-${GLIDE_PROXY_PORT}.app.github.dev"
  else
    url="http://localhost:${GLIDE_PROXY_PORT}"
  fi
  printf '%s' "$url"
}

glide_selkies_bin() {
  if [ -x "$GLIDE_HOME/bin/selkies" ]; then
    printf '%s' "$GLIDE_HOME/bin/selkies"
  elif command -v selkies >/dev/null 2>&1; then
    command -v selkies
  fi
}



# shellcheck source=profile.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/profile.sh"
# shellcheck source=game.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/game.sh"
