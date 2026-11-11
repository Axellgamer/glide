#!/usr/bin/env bash
# Durable, non-secret user profile.
#
# The canonical copy lives in the repository at .glide/profile.env, so it
# survives deleting or replacing the codespace. Everything in it is safe to
# commit: no passwords, no tokens, no Microsoft credentials.

GLIDE_PROFILE_FILE="${GLIDE_PROFILE_FILE:-$GLIDE_ROOT/.glide/profile.env}"
GLIDE_SYNC_URL="${GLIDE_SYNC_URL:-https://glide-profile-sync.amphibianclientlauncher.workers.dev}"
GLIDE_SYNC_KEY_FILE="${GLIDE_SYNC_KEY_FILE:-$GLIDE_HOME/sync.key}"
GLIDE_PROFILE_KEYS=(
  GLIDE_MINECRAFT_VERSION
  GLIDE_MINECRAFT_LOADER
  GLIDE_MINECRAFT_XMX
  GLIDE_RESOLUTION
  GLIDE_FPS
  GLIDE_BITRATE
  GLIDE_ENCODER
  GLIDE_DASHBOARD
  GLIDE_AUDIO
  GLIDE_AUTH_MODE
  GLIDE_OFFLINE_USERNAME
  GLIDE_MICROSOFT_CLIENT_ID
  GLIDE_MAX_RESTARTS
  GLIDE_RENDERER
)

glide_profile_allowed() {
  local needle="$1" key
  for key in "${GLIDE_PROFILE_KEYS[@]}"; do
    [ "$key" = "$needle" ] && return 0
  done
  return 1
}

# Copy repository profile values over the local session env (local-only keys
# such as GLIDE_SELKIES_PASSWORD are preserved).
glide_profile_import() {
  [ -f "$GLIDE_PROFILE_FILE" ] || return 0
  glide_ensure_dirs
  [ -f "$GLIDE_SESSION_ENV" ] || glide_write_defaults
  local tmp="$GLIDE_SESSION_ENV.import" key value next
  cp -f "$GLIDE_SESSION_ENV" "$tmp" 2>/dev/null || : >"$tmp"
  while IFS='=' read -r key value || [ -n "${key:-}" ]; do
    key="$(printf '%s' "${key:-}" | tr -d '[:space:]')"
    value="$(printf '%s' "${value:-}" | sed 's/[[:space:]]*$//')"
    [ -n "$key" ] || continue
    case "$key" in \#*) continue ;; esac
    glide_profile_allowed "$key" || continue
    [ -n "$value" ] || continue
    next="$tmp.next"
    awk -v k="$key" -v v="$value" 'BEGIN{FS=OFS="="} $1==k{print k"="v; next} {print}' \
      "$tmp" >"$next" 2>/dev/null || : >"$next"
    mv "$next" "$tmp"
    if ! grep -q "^${key}=" "$tmp" 2>/dev/null; then
      printf '%s=%s\n' "$key" "$value" >>"$tmp"
    fi
  done <"$GLIDE_PROFILE_FILE"
  mv "$tmp" "$GLIDE_SESSION_ENV"
}

# Write the current local settings to .glide/profile.env.
glide_profile_export() {
  mkdir -p "$(dirname "$GLIDE_PROFILE_FILE")"
  local tmp="$GLIDE_PROFILE_FILE.tmp" key value
  {
    printf '# Glide profile - non-secret settings, safe to commit.\n'
    printf '# Written by the codespace; edit from the menu or session.env instead.\n'
    for key in "${GLIDE_PROFILE_KEYS[@]}"; do
      value="$(awk -F= -v k="$key" '$1==k { sub(/^[^=]*=/, ""); print; exit }' "$GLIDE_SESSION_ENV" 2>/dev/null)"
      [ -n "$value" ] && printf '%s=%s\n' "$key" "$value"
    done
  } >"$tmp"
  mv "$tmp" "$GLIDE_PROFILE_FILE"
}

# Commit the profile to the user's fork through the GitHub Contents API, using
# the Codespaces GITHUB_TOKEN. If no token/repo is available (local shell), the
# file is still written and the caller can commit it normally.
glide_profile_repo() {
  local repo="${GITHUB_REPOSITORY:-}"
  if [ -z "$repo" ]; then
    repo="$(git -C "$GLIDE_ROOT" remote get-url origin 2>/dev/null \
      | sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$#\1#')"
  fi
  printf '%s' "$repo"
}

glide_profile_branch() {
  local branch="${GITHUB_REF_NAME:-}"
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    branch="$(git -C "$GLIDE_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  fi
  printf '%s' "$branch"
}

glide_sync_key() {
  [ -f "$GLIDE_SYNC_KEY_FILE" ] || return 1
  local key
  key="$(tr -d '[:space:]' <"$GLIDE_SYNC_KEY_FILE" 2>/dev/null)"
  printf '%s' "$key" | grep -Eq '^[a-f0-9]{64}$' || return 1
  printf '%s' "$key"
}

glide_sync_push() {
  local key output
  key="$(glide_sync_key)" || return 0
  output="$(GLIDE_SYNC_KEY="$key" GLIDE_SYNC_URL="$GLIDE_SYNC_URL" \
    python3 "$GLIDE_ROOT/codespace/profile_remote.py" push "$GLIDE_PROFILE_FILE" 2>&1)"
  if [ "$?" -eq 0 ]; then
    glide_log "profile pushed to the portable store"
  else
    glide_log "portable profile push failed: $output"
  fi
  return 0
}

# 0 = profile available (updated/unchanged), 2 = no profile yet, 1 = error
glide_sync_pull() {
  local key output
  key="$(glide_sync_key)" || return 2
  output="$(GLIDE_SYNC_KEY="$key" GLIDE_SYNC_URL="$GLIDE_SYNC_URL" \
    python3 "$GLIDE_ROOT/codespace/profile_remote.py" pull "$GLIDE_PROFILE_FILE" 2>&1)"
  local rc=$?
  case "$rc" in
    0)
      [ "$output" = "updated" ] && glide_log "profile restored from the portable store"
      return 0
      ;;
    3) return 2 ;;
    *)
      glide_log "portable profile pull failed: $output"
      return 1
      ;;
  esac
}

glide_profile_linked() {
  glide_sync_key >/dev/null 2>&1
}

# Link this codespace/account to a passphrase-keyed portable profile. The
# passphrase is not stored; only its derived key lives in ~/.glide/sync.key
# (mode 600), so a different account can re-link with the same passphrase.
glide_profile_link() {
  if [ ! -t 0 ]; then
    glide_log "linking needs an interactive terminal"
    return 2
  fi
  local pass confirm key rc
  printf 'Choose a profile passphrase (10+ characters).\n'
  printf 'Use the same passphrase on any GitHub account to restore these settings.\n'
  read -rsp "Passphrase: " pass || return 2
  printf '\n'
  if [ "${#pass}" -lt 10 ]; then
    printf 'Passphrase must be at least 10 characters.\n' >&2
    return 2
  fi
  read -rsp "Repeat: " confirm || return 2
  printf '\n'
  if [ "$pass" != "$confirm" ]; then
    printf 'Passphrases do not match.\n' >&2
    return 2
  fi
  key="$(printf '%s' "$pass" | python3 -c 'import hashlib,sys; print(hashlib.sha256(("glide-profile-v1:"+sys.stdin.read()).encode()).hexdigest())')"
  umask 077
  printf '%s\n' "$key" >"$GLIDE_SYNC_KEY_FILE"
  chmod 600 "$GLIDE_SYNC_KEY_FILE"
  glide_sync_pull
  rc=$?
  if [ "$rc" -eq 0 ]; then
    glide_profile_import
    glide_load_env >/dev/null 2>&1 || true
    glide_profile_sync "linked"
    glide_log "profile linked; settings restored"
    return 0
  fi
  if [ "$rc" -eq 2 ]; then
    glide_profile_sync "initial link"
    glide_log "profile linked; current settings uploaded"
    return 0
  fi
  glide_log "profile key saved, but the portable store could not be reached"
  return 1
}

glide_profile_unlink() {
  rm -f "$GLIDE_SYNC_KEY_FILE"
  glide_log "portable profile unlinked; this codespace uses the fork copy only"
}

# Pull the profile on boot so a resumed codespace sees settings saved by
# another one. Portable store first, fork second. Never fatal.
glide_profile_pull() {
  mkdir -p "$(dirname "$GLIDE_PROFILE_FILE")"
  [ -f "$GLIDE_PROFILE_FILE" ] || : >"$GLIDE_PROFILE_FILE"
  if glide_profile_linked; then
    glide_sync_pull
    case "$?" in
      0) return 0 ;;
      2) : ;; # no portable profile yet; try the fork
      *) : ;; # network error; fall back to the fork copy
    esac
  fi
  if [ -z "${GITHUB_TOKEN:-}" ] && [ -z "${GH_TOKEN:-}" ]; then
    return 0
  fi
  local repo branch output
  repo="$(glide_profile_repo)"
  branch="$(glide_profile_branch)"
  [ -n "$repo" ] && [ -n "$branch" ] || return 0
  output="$(GLIDE_PROFILE_REPO="$repo" GLIDE_PROFILE_BRANCH="$branch" \
    python3 "$GLIDE_ROOT/codespace/profile_fetch.py" "$GLIDE_PROFILE_FILE" 2>&1)"
  case "$output" in
    updated) glide_log "profile pulled from $repo@$branch" ;;
    missing | unchanged | "") ;;
    *) glide_log "profile pull: $output" ;;
  esac
  return 0
}

glide_profile_sync() {
  local reason="${1:-settings}" repo branch output
  glide_profile_export
  glide_sync_push
  if [ -z "${GITHUB_TOKEN:-}" ] && [ -z "${GH_TOKEN:-}" ]; then
    glide_log "profile written to .glide/profile.env (no repository token; commit it manually)"
    return 0
  fi
  repo="$(glide_profile_repo)"
  branch="$(glide_profile_branch)"
  if [ -z "$repo" ] || [ -z "$branch" ]; then
    glide_log "profile written to .glide/profile.env (no repository/branch; commit it manually)"
    return 0
  fi
  output="$(GLIDE_PROFILE_REPO="$repo" GLIDE_PROFILE_BRANCH="$branch" \
    GLIDE_PROFILE_REASON="$reason" \
    python3 "$GLIDE_ROOT/codespace/profile_sync.py" "$GLIDE_PROFILE_FILE" 2>&1)"
  if [ "$?" -eq 0 ]; then
    glide_log "profile saved to $repo@$branch"
  else
    glide_log "profile sync failed: $output"
  fi
  return 0
}
