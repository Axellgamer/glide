#!/usr/bin/env bash
# Worlds, mods, resource packs and shader packs in the portable store.
# Requires glide link. The archive is chunked by the Worker (40 MB cap).

GLIDE_DATA_ITEMS=(saves mods resourcepacks shaderpacks)

glide_data_bundle() {
  local out="$GLIDE_HOME/world-data.tgz" item
  local items=()
  for item in "${GLIDE_DATA_ITEMS[@]}"; do
    [ -e "$GLIDE_MC/$item" ] && items+=("$item")
  done
  [ "${#items[@]}" -gt 0 ] || return 1
  tar -C "$GLIDE_MC" -czf "$out" "${items[@]}" 2>/dev/null || return 1
  printf '%s' "$out"
}

glide_data_push() {
  glide_profile_linked || return 0
  local archive output size
  archive="$(glide_data_bundle)" || return 0
  size="$(du -h "$archive" 2>/dev/null | awk '{print $1}')"
  output="$(GLIDE_SYNC_KEY="$(glide_sync_key)" GLIDE_SYNC_URL="$GLIDE_SYNC_URL" \
    python3 "$GLIDE_ROOT/codespace/data_remote.py" push "$archive" 2>&1)"
  rm -f "$archive"
  case "$output" in
    pushed) glide_log "worlds/mods/packs saved to the portable store (${size:-?})" ;;
    *) glide_log "worlds/mods/packs push: $output" ;;
  esac
  return 0
}

# 0 = applied, 2 = nothing stored, 1 = error
glide_data_pull() {
  glide_profile_linked || return 2
  local archive="$GLIDE_HOME/world-data.pull.tgz" output rc
  output="$(GLIDE_SYNC_KEY="$(glide_sync_key)" GLIDE_SYNC_URL="$GLIDE_SYNC_URL" \
    python3 "$GLIDE_ROOT/codespace/data_remote.py" pull "$archive" 2>&1)"
  rc=$?
  case "$rc" in
    0)
      tar -C "$GLIDE_MC" -xzf "$archive" 2>/dev/null || true
      rm -f "$archive"
      glide_log "worlds/mods/packs restored from the portable store"
      return 0
      ;;
    3)
      rm -f "$archive"
      return 2
      ;;
    *)
      rm -f "$archive"
      glide_log "worlds/mods/packs pull: $output"
      return 1
      ;;
  esac
}

glide_link_data() {
  declare -F glide_data_pull >/dev/null 2>&1 || return 0
  if glide_pid_alive "$GLIDE_RUN_DIR/minecraft.pid"; then
    glide_log "worlds/mods restore deferred: restart the game while stopped to apply"
    return 0
  fi
  local rc
  glide_data_pull
  rc=$?
  case "$rc" in
    0) glide_log "worlds/mods/packs restored" ;;
    2) glide_data_push ;;
  esac
  return 0
}
