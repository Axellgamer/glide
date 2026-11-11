#!/usr/bin/env bash
# Glide Codespace - one time provisioner.
#
# Installs everything a codespace needs to host a streamed Minecraft client:
# virtual display, audio, Selkies, the proxy, Java runtimes and the Python
# launcher library. Safe to re-run; it skips work already done.
#
#   bash codespace/setup.sh            # normal
#   GLIDE_BUILD_BRIDGE=1 bash codespace/setup.sh   # also build the Rust GL bridge
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

glide_ensure_dirs
SETUP_LOG="$GLIDE_LOG_DIR/setup.log"
exec > >(tee -a "$SETUP_LOG") 2>&1

glide_log "Glide setup starting (root=$GLIDE_ROOT, home=$GLIDE_HOME)"

MARKER="$GLIDE_HOME/setup.stamp"
STAMP="$( (cat "$HERE/setup.sh" "$HERE/lib.sh") | sha256sum | cut -d' ' -f1)"
if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$STAMP" ] && [ "${1:-}" != "--force" ]; then
  if glide_have selkies || [ -x "$GLIDE_HOME/bin/selkies" ]; then
    glide_log "Already provisioned (stamp $STAMP). Use --force to redo."
    exit 0
  fi
fi

apt_install_tolerant() {
  # Install in one shot for speed; fall back to one by one so a package that
  # does not exist in this Ubuntu release cannot abort the whole run.
  local packages=("$@") pkg failed=()
  # libasound2 was renamed to libasound2t64 in Ubuntu 24.04.
  local normalized=()
  for pkg in "${packages[@]}"; do
    normalized+=("$pkg")
  done
  if glide_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    "${normalized[@]}" >/dev/null 2>&1; then
    return 0
  fi
  for pkg in "${normalized[@]}"; do
    if ! glide_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      "$pkg" >/dev/null 2>&1; then
      failed+=("$pkg")
    fi
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    glide_log "optional packages unavailable: ${failed[*]}"
  fi
  return 0
}

glide_log "installing system packages"
glide_sudo apt-get update -y >/dev/null 2>&1 || glide_log "apt-get update failed, continuing"
apt_install_tolerant \
  ca-certificates curl jq unzip xz-utils procps \
  xvfb x11-utils x11-xserver-utils xauth xdotool \
  pulseaudio pulseaudio-utils \
  libgl1 libglx-mesa0 libgl1-mesa-dri libgbm1 mesa-utils \
  libx11-6 libxext6 libxrender1 libxtst6 libxi6 libxcursor1 libxrandr2 \
  libxinerama1 libxxf86vm1 libpulse0 libopenal1 \
  ffmpeg nginx \
  python3 python3-venv python3-pip \
  fonts-dejavu-core fontconfig

# libasound2 is libasound2t64 on 24.04+; one of the two exists everywhere.
apt_install_tolerant libasound2t64
apt_install_tolerant libasound2

# A tiny window manager keeps the Minecraft window tiled to the full screen.
apt_install_tolerant dwm
if ! glide_have dwm; then
  glide_log "dwm not available - the stream will run without a window manager"
fi

# ---------------------------------------------------------------- Java ------
ensure_jre() {
  local major="$1" dest="$GLIDE_JRE/$1" arch
  if [ -x "$dest/bin/java" ]; then
    glide_log "java $major already installed"
    return 0
  fi
  case "$(uname -m)" in
    x86_64 | amd64) arch="x64" ;;
    aarch64 | arm64) arch="aarch64" ;;
    *) arch="x64" ;;
  esac
  glide_log "downloading Temurin JRE $major ($arch)"
  mkdir -p "$dest"
  local url="https://api.adoptium.net/v3/binary/latest/${major}/ga/linux/${arch}/jre/hotspot/normal/eclipse"
  if ! curl -fsSL --retry 3 --connect-timeout 20 --max-time 600 -o "/tmp/glide-jre-$major.tgz" "$url"; then
    glide_log "could not download Java $major"
    return 1
  fi
  tar -xzf "/tmp/glide-jre-$major.tgz" -C "$dest" --strip-components=1
  rm -f "/tmp/glide-jre-$major.tgz"
  [ -x "$dest/bin/java" ] && glide_log "java $major ready: $("$dest/bin/java" -version 2>&1 | head -n1)"
}

ensure_jre 21 || glide_die "Java 21 install failed"
ensure_jre 8 || glide_log "Java 8 unavailable - Minecraft 1.12.x will not launch"

# ------------------------------------------------------- python launcher ----
if [ ! -x "$GLIDE_VENV/bin/python" ]; then
  glide_log "creating python venv"
  python3 -m venv "$GLIDE_VENV"
fi
glide_log "installing minecraft-launcher-lib"
"$GLIDE_VENV/bin/pip" install --quiet --upgrade pip >/dev/null 2>&1 || true
if ! "$GLIDE_VENV/bin/pip" install --quiet "minecraft-launcher-lib==8.0" "requests>=2.31"; then
  glide_die "could not install minecraft-launcher-lib"
fi
"$GLIDE_VENV/bin/python" -c 'import minecraft_launcher_lib; print("launcher-lib ok")'

# --------------------------------------------------------------- Selkies ----
install_selkies_deb() {
  local version="$1" pkg="$2" url
  url="https://github.com/selkies-project/selkies/releases/download/${version}/${pkg}"
  glide_log "downloading $pkg"
  curl -fL --retry 4 --retry-all-errors --connect-timeout 20 --max-time 600 \
    -o "/tmp/$pkg" "$url" || return 1
  glide_sudo apt-get install -y "/tmp/$pkg" || return 1
  rm -f "/tmp/$pkg"
  command -v selkies >/dev/null 2>&1
}

install_selkies_appimage() {
  local version="$1" app arch silent
  case "$(uname -m)" in
    x86_64 | amd64) arch="x86_64" ;;
    aarch64 | arm64) arch="aarch64" ;;
    *) arch="$(uname -m)" ;;
  esac
  app="selkies-${version}-${arch}.AppImage"
  glide_log "falling back to the Selkies AppImage ($app)"
  mkdir -p "$GLIDE_HOME/bin"
  curl -fL --retry 4 --retry-all-errors --connect-timeout 20 --max-time 900 \
    -o "$GLIDE_HOME/bin/selkies.AppImage" \
    "https://github.com/selkies-project/selkies/releases/download/${version}/${app}" || return 1
  chmod +x "$GLIDE_HOME/bin/selkies.AppImage"
  cat >"$GLIDE_HOME/bin/selkies" <<'WRAPPER'
#!/usr/bin/env bash
export APPIMAGE_EXTRACT_AND_RUN=1
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/selkies.AppImage" "$@"
WRAPPER
  chmod +x "$GLIDE_HOME/bin/selkies"
  return 0
}

install_selkies() {
  glide_log "resolving latest Selkies release"
  local version distro arch pkg candidate
  version="$(curl -fsSL --connect-timeout 20 "https://api.github.com/repos/selkies-project/selkies/releases/latest" | jq -r '.tag_name // empty')"
  if [ -z "$version" ]; then
    glide_log "could not resolve Selkies version"
    return 1
  fi
  glide_log "Selkies $version"
  # shellcheck disable=SC1091
  distro="$(. /etc/os-release && printf '%s%s' "$ID" "${VERSION_ID:-}")"
  arch="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  for candidate in "$distro" "ubuntu24.04" "ubuntu22.04" "debianbookworm"; do
    pkg="selkies-${version}-${candidate}-${arch}.deb"
    if install_selkies_deb "$version" "$pkg"; then
      printf '%s' "$version" >"$GLIDE_HOME/selkies.version"
      glide_log "Selkies installed (deb, $candidate)"
      return 0
    fi
  done
  if install_selkies_appimage "$version"; then
    printf '%s' "$version" >"$GLIDE_HOME/selkies.version"
    glide_log "Selkies installed (AppImage)"
    return 0
  fi
  return 1
}

if glide_have selkies || [ -x "$GLIDE_HOME/bin/selkies" ]; then
  glide_log "Selkies already installed: $("$GLIDE_HOME/bin/selkies" --version 2>/dev/null || selkies --version 2>/dev/null || echo unknown)"
else
  install_selkies || glide_die "Selkies install failed - see $SETUP_LOG"
fi

# ------------------------------------------------- Rust GL bridge (opt in) ---
if [ "${GLIDE_BUILD_BRIDGE:-0}" = "1" ]; then
  if glide_have cargo; then
    glide_log "building glide-gl-bridge (this can take a few minutes)"
    apt_install_tolerant pkg-config libx11-dev
    if cargo build --release --features vulkan --manifest-path "$GLIDE_REPO_CLIENT/glide-gl-bridge/Cargo.toml"; then
      glide_log "GL bridge built"
    else
      glide_log "GL bridge build failed - continuing without it"
    fi
  else
    glide_log "GLIDE_BUILD_BRIDGE=1 but cargo is missing - skipping bridge"
  fi
fi

# ----------------------------------------------- runtime agent (optional) ---
if glide_have javac && glide_have jar; then
  bash "$GLIDE_REPO_CLIENT/glide-runtime-agent/build.sh" >/dev/null 2>&1 \
    && glide_log "runtime agent built" \
    || glide_log "runtime agent build failed (optional)"
fi

# --------------------------------------------------------------- helpers ----
mkdir -p "$HOME/.local/bin"
ln -sf "$HERE/glide" "$HOME/.local/bin/glide"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) glide_log "note: $HOME/.local/bin is not on PATH; call ./codespace/glide instead" ;;
esac

printf '%s' "$STAMP" >"$MARKER"
glide_log "setup complete - next: ./codespace/glide up"
