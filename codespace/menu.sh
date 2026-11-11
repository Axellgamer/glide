#!/usr/bin/env bash
# Interactive launcher for github.dev / VS Code.
# Runs on attach and from the "Glide: Menu" task. No web frontend.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

glide_ensure_dirs
glide_load_env

GLIDE="$HERE/glide"
LOADERS=(vanilla fabric legacy-fabric forge legacy-forge quilt neoforge)
HEAPS=(2G 3G 4G 6G 8G)

clear_screen() {
  if [ -t 1 ]; then printf '\033[2J\033[H'; fi
}

pause() {
  printf '\n'
  read -r -p "Press Enter to return to the menu… " _ || true
}

stage_line() {
  local stage detail
  stage="$(awk -F= '$1=="STAGE"{sub(/^[^=]*=/,"");print;exit}' "$GLIDE_STATE_FILE" 2>/dev/null)"
  detail="$(awk -F= '$1=="DETAIL"{sub(/^[^=]*=/,"");print;exit}' "$GLIDE_STATE_FILE" 2>/dev/null)"
  printf '%s' "${stage:-idle}${detail:+ — $detail}"
}

header() {
  clear_screen
  printf 'Glide Codespace\n'
  printf '  %s\n' "────────────────────────────────────────────────────────"
  printf '  Minecraft  %s / %s / %s\n' "$GLIDE_MINECRAFT_VERSION" "$GLIDE_MINECRAFT_LOADER" "$GLIDE_MINECRAFT_XMX"
  printf '  State      %s\n' "$(stage_line)"
  printf '  Stream     %s\n' "$(glide_public_url)"
  printf '  Note       keep port 6080 private; open it from github.dev or a signed-in tab.\n'
  printf '  Files      use the Explorer in the left sidebar (Client/ and ~/.glide/minecraft).\n'
  if glide_profile_linked; then
    printf '  Profile    portable store + fork (linked)\n'
  else
    printf '  Profile    fork only — use l to link across GitHub accounts.\n'
  fi
  printf '  %s\n\n' "────────────────────────────────────────────────────────"
  printf '  1  Start / restart session      6  Stream profile\n'
  printf '  2  Stop session                7  Show status\n'
  printf '  3  Restart game                8  Tail a log\n'
  printf '  4  Restart stream              9  Open session.env\n'
  printf '  5  Switch installation         s  Save settings\n'
  printf '  l  Link profile (switch accounts)   0  Quit\n\n'
}

switch_installation() {
  local version loader heap i choice
  printf 'Minecraft version [%s]: ' "$GLIDE_MINECRAFT_VERSION"
  read -r version || return
  version="${version:-$GLIDE_MINECRAFT_VERSION}"

  printf '\nLoaders:\n'
  for i in "${!LOADERS[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${LOADERS[$i]}"; done
  printf 'Loader [%s]: ' "$GLIDE_MINECRAFT_LOADER"
  read -r choice || return
  if [ -z "$choice" ]; then
    loader="$GLIDE_MINECRAFT_LOADER"
  elif printf '%s' "$choice" | grep -Eq '^[0-9]+$' && [ "$choice" -ge 1 ] && [ "$choice" -le "${#LOADERS[@]}" ]; then
    loader="${LOADERS[$((choice - 1))]}"
  else
    loader="$choice"
  fi

  printf '\nHeap:\n'
  for i in "${!HEAPS[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${HEAPS[$i]}"; done
  printf 'Heap [%s]: ' "$GLIDE_MINECRAFT_XMX"
  read -r choice || return
  if [ -z "$choice" ]; then
    heap="$GLIDE_MINECRAFT_XMX"
  elif printf '%s' "$choice" | grep -Eq '^[0-9]+$' && [ "$choice" -ge 1 ] && [ "$choice" -le "${#HEAPS[@]}" ]; then
    heap="${HEAPS[$((choice - 1))]}"
  else
    heap="$choice"
  fi

  bash "$GLIDE" install "$version" "$loader" "$heap"
}

pick_profile() {
  local choice
  printf '1) low   2) medium   3) high\n'
  read -r -p 'Profile: ' choice || return
  case "$choice" in
    1 | low) bash "$GLIDE" profile low ;;
    2 | medium) bash "$GLIDE" profile medium ;;
    3 | high) bash "$GLIDE" profile high ;;
    *) printf 'cancelled\n' ;;
  esac
}

tail_log() {
  local choice
  printf '1) launcher  2) java  3) boot  4) selkies  5) nginx\n'
  read -r -p 'Log: ' choice || return
  case "$choice" in
    1) bash "$GLIDE" logs minecraft 120 ;;
    2) bash "$GLIDE" logs game 120 ;;
    3) bash "$GLIDE" logs boot 120 ;;
    4) bash "$GLIDE" logs selkies 120 ;;
    5) bash "$GLIDE" logs nginx 120 ;;
    *) printf 'cancelled\n' ;;
  esac
}

while true; do
  header
  read -r -p '  Select: ' choice || exit 0
  case "${choice// /}" in
    1) bash "$GLIDE" up; sleep 1 ;;
    2) bash "$GLIDE" down ;;
    3) bash "$GLIDE" restart-game ;;
    4) bash "$GLIDE" restart-stream ;;
    5) switch_installation; pause ;;
    6) pick_profile; pause ;;
    7) bash "$GLIDE" status; pause ;;
    8) tail_log; pause ;;
    9) bash "$GLIDE" env ;;
    s | S) bash "$GLIDE" sync; pause ;;
    l | L) bash "$GLIDE" link; pause ;;
    q | Q | 0 | "") exit 0 ;;
    *) printf 'unknown choice\n' ;;
  esac
done
