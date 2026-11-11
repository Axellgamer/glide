#!/usr/bin/env bash
# Small game settings (not worlds/packs) that follow the user across
# codespaces/accounts through the portable store. Requires glide link.

GLIDE_GAME_ITEMS=(options.txt optionsof.txt optionsshaders.txt servers.dat config)

glide_game_bundle() {
  local out="$GLIDE_HOME/game-settings.tgz" item
  local items=()
  for item in "${GLIDE_GAME_ITEMS[@]}"; do
    [ -e "$GLIDE_MC/$item" ] && items+=("$item")
  done
  [ "${#items[@]}" -gt 0 ] || return 1
  tar -C "$GLIDE_MC" -czf "$out" "${items[@]}" 2>/dev/null || return 1
  printf '%s' "$out"
}

glide_game_push() {
  glide_profile_linked || return 0
  local archive output
  archive="$(glide_game_bundle)" || return 0
  output="$(GLIDE_SYNC_KEY="$(glide_sync_key)" GLIDE_SYNC_URL="$GLIDE_SYNC_URL" \
    python3 "$GLIDE_ROOT/codespace/game_remote.py" push "$archive" 2>&1)"
  rm -f "$archive"
  case "$output" in
    pushed) glide_log "game settings saved to the portable store" ;;
    *) glide_log "game settings push: $output" ;;
  esac
  return 0
}

# 0 = applied or unchanged, 2 = nothing stored yet, 1 = error
glide_game_pull() {
  glide_profile_linked || return 2
  local archive="$GLIDE_HOME/game-settings.pull.tgz" output rc
  output="$(GLIDE_SYNC_KEY="$(glide_sync_key)" GLIDE_SYNC_URL="$GLIDE_SYNC_URL" \
    python3 "$GLIDE_ROOT/codespace/game_remote.py" pull "$archive" 2>&1)"
  rc=$?
  case "$rc" in
    0)
      tar -C "$GLIDE_MC" -xzf "$archive" 2>/dev/null || true
      rm -f "$archive"
      glide_log "game settings restored from the portable store"
      return 0
      ;;
    3)
      rm -f "$archive"
      return 2
      ;;
    *)
      rm -f "$archive"
      glide_log "game settings pull: $output"
      return 1
      ;;
  esac
}
