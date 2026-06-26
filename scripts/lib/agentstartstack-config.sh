#!/usr/bin/env bash
# Load .agentstartstack.env from a host project repo root.
# Sourced by init scripts; do not execute directly.

agentstartstack_load_config() {
  local start_dir="${1:-}"
  local dir config_file

  if [[ -z "$start_dir" ]]; then
    start_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  fi
  dir="$(readlink -f "$start_dir")"

  while [[ "$dir" != "/" ]]; do
    config_file="${dir}/.agentstartstack.env"
    if [[ -f "$config_file" ]]; then
      # shellcheck source=/dev/null
      source "$config_file"
      AGENTSTARTSTACK_HOST_ROOT="$dir"
      AGENTSTARTSTACK_CONFIG_FILE="$config_file"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  return 1
}

agentstartstack_apply_defaults() {
  PROJECT_NAME="${PROJECT_NAME:-}"
  DISPLAY_NAME="${DISPLAY_NAME:-$PROJECT_NAME}"
  CANONICAL_LOCAL_REPO="${CANONICAL_LOCAL_REPO:-}"
  ORIGIN_URL="${ORIGIN_URL:-}"
  ACTIVE_GUARD_PGREP="${ACTIVE_GUARD_PGREP:-}"

  if [[ -z "$PROJECT_NAME" ]]; then
    echo "[ERR]  PROJECT_NAME not set in .agentstartstack.env" >&2
    return 1
  fi

  # Default the canonical repo to the host project root (where .agentstartstack.env
  # lives) -- no assumption about where the human keeps their checkouts. Override
  # by setting CANONICAL_LOCAL_REPO in .agentstartstack.env.
  if [[ -z "$CANONICAL_LOCAL_REPO" ]]; then
    CANONICAL_LOCAL_REPO="${AGENTSTARTSTACK_HOST_ROOT:-}"
  fi

  CANONICAL_LOCAL_REPO="$(cd "$CANONICAL_LOCAL_REPO" 2>/dev/null && pwd)" || {
    echo "[ERR]  CANONICAL_LOCAL_REPO not found: ${CANONICAL_LOCAL_REPO:-<unset>}" >&2
    return 1
  }

  # Colon-separated parent dirs under which agent session clones live. Single
  # source of truth for both the init scripts and ass's clone discovery (which
  # matches clones by git origin URL -- no project-specific subdir naming assumed).
  AGENT_SESSION_CLONE_PARENT="${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"

  return 0
}

# Set GENERIC_GUIDANCE_DIR and PROJECT_GUIDANCE_DIR from host repo layout.
agentstartstack_resolve_guidance_paths() {
  local root="${1:-${AGENTSTARTSTACK_HOST_ROOT:-}}"

  [[ -n "$root" ]] || return 1

  # Generic guidance: the submodule's docs (consumer) or this template's own.
  if [[ -d "${root}/.agentstartstack/agentstartstack" ]]; then
    GENERIC_GUIDANCE_DIR=".agentstartstack/agentstartstack"
  elif [[ -d "${root}/agentstartstack/agentstartstack" ]]; then
    GENERIC_GUIDANCE_DIR="agentstartstack/agentstartstack"
  elif [[ -d "${root}/docs" ]]; then
    GENERIC_GUIDANCE_DIR="docs"
  elif [[ -d "${root}/docs" ]]; then
    GENERIC_GUIDANCE_DIR="docs"
  elif [[ -d "${root}/agentstartstack" ]]; then
    GENERIC_GUIDANCE_DIR="agentstartstack"
  else
    echo "[ERR]  No agentstartstack guidance directory found under: $root" >&2
    return 1
  fi

  # Project-specific guidance SHALL live in docs/ (CANONICAL_LOCAL_REPO/docs).
  # The legacy name was agentstartstack/, which collides with the template and
  # confuses contributors; fall back to it only for not-yet-migrated consumers.
  if [[ -d "${root}/docs" ]]; then
    PROJECT_GUIDANCE_DIR="docs"
  elif [[ "$GENERIC_GUIDANCE_DIR" != "agentstartstack" && -d "${root}/agentstartstack" ]]; then
    PROJECT_GUIDANCE_DIR="agentstartstack"
  else
    PROJECT_GUIDANCE_DIR="docs"
  fi

  return 0
}

# Backstop for the bump-delta protocol: detect a pending agentstartstack reconcile
# even when no .agentstartstack-bump watch file is present -- e.g. ass up --all
# deferred an action-bearing bump (it does not auto-commit those). Echoes the
# range "OLD..NEW" and returns 0 if the .agentstartstack submodule is behind its
# remote; returns 1 (no output) otherwise, including the template repo (no
# submodule) and offline.
agentstartstack_pending_reconcile() {
  local root="${1:-${AGENTSTARTSTACK_HOST_ROOT:-}}"
  local sub head upstream
  sub="${root}/.agentstartstack"

  [[ -e "${sub}/.git" ]] || return 1
  git -C "$sub" fetch -q origin main 2>/dev/null || return 1
  head=$(git -C "$sub" rev-parse HEAD 2>/dev/null) || return 1
  upstream=$(git -C "$sub" rev-parse origin/main 2>/dev/null) || return 1

  [[ "$head" != "$upstream" ]] || return 1
  if [[ -n "$(git -C "$sub" rev-list "${head}..${upstream}" 2>/dev/null)" ]]; then
    printf '%s..%s\n' "$head" "$upstream"
    return 0
  fi
  return 1
}

# True if commit $2 in repo $1 carries a CONSUMER-ACTION: line in its message.
agentstartstack_commit_has_consumer_action() {
  local repo="$1" sha="$2"
  git -C "$repo" log -1 --format='%B' "$sha" 2>/dev/null \
    | grep -q '^[[:space:]]*CONSUMER-ACTION:'
}

# Echo the newest (latest) producer commit in $2 that carries CONSUMER-ACTION:.
# $1 = path to .agentstartstack checkout; $2 = git revision range (e.g. OLD..NEW).
agentstartstack_latest_action_commit_in_range() {
  local sub="$1" range="$2" sha last=""

  [[ -n "$range" ]] || return 1
  while IFS= read -r sha; do
    [[ -n "$sha" ]] || continue
    if agentstartstack_commit_has_consumer_action "$sub" "$sha"; then
      last="$sha"
    fi
  done < <(git -C "$sub" log --reverse --format='%H' "$range" 2>/dev/null)

  [[ -n "$last" ]] && printf '%s\n' "$last"
}

# Read the consumer's CONSUMER-ACTION watermark (full SHA) from repo root.
# Echoes nothing and returns 1 when missing or invalid.
agentstartstack_read_action_seen() {
  local root="${1:-${AGENTSTARTSTACK_HOST_ROOT:-}}"
  local seen_file="${root}/.agentstartstack-action-seen" seen

  [[ -f "$seen_file" ]] || return 1
  seen=$(tr -d '[:space:]' < "$seen_file")
  [[ "$seen" =~ ^[0-9a-f]{40}$ ]] || return 1
  printf '%s\n' "$seen"
}

# After reconciling OLD..NEW, record the latest action-bearing producer commit.
# No-op when the delta has no CONSUMER-ACTION commits. Returns 0 either way.
agentstartstack_record_action_seen_from_delta() {
  local root="$1" old="$2" new="$3"
  local sub="${root}/.agentstartstack" latest

  [[ -e "${sub}/.git" ]] || return 1
  latest=$(agentstartstack_latest_action_commit_in_range "$sub" "${old}..${new}") || true
  [[ -n "$latest" ]] || return 0

  printf '%s\n' "$latest" > "${root}/.agentstartstack-action-seen"
  return 0
}

# Backstop: submodule pointer is current but CONSUMER-ACTION(s) after the recorded
# watermark were never performed (e.g. a pre-action-aware blind bump). Echoes
# "OLD..NEW" for the pending action delta and returns 0; returns 1 otherwise.
agentstartstack_pending_consumer_actions() {
  local root="${1:-${AGENTSTARTSTACK_HOST_ROOT:-}}"
  local sub="${root}/.agentstartstack" head seen seen_file range start

  [[ -e "${sub}/.git" ]] || return 1
  head=$(git -C "$sub" rev-parse HEAD 2>/dev/null) || return 1

  seen=""
  if seen_file=$(agentstartstack_read_action_seen "$root" 2>/dev/null); then
    seen="$seen_file"
  fi

  if [[ -n "$seen" ]]; then
    if ! git -C "$sub" cat-file -e "${seen}^{commit}" 2>/dev/null; then
      seen=""
    elif [[ "$seen" == "$head" ]]; then
      return 1
    elif ! git -C "$sub" merge-base --is-ancestor "$seen" "$head" 2>/dev/null; then
      seen=""
    else
      range="${seen}..${head}"
    fi
  fi

  if [[ -z "$seen" ]]; then
    start=$(git -C "$sub" rev-list --max-parents=0 HEAD 2>/dev/null | head -1) || return 1
    [[ -n "$start" ]] || return 1
    if [[ "$start" == "$head" ]]; then
      range="$head"
    else
      range="${start}..${head}"
    fi
  fi

  if ! git -C "$sub" log --format='%B' "$range" 2>/dev/null \
        | grep -q '^[[:space:]]*CONSUMER-ACTION:'; then
    return 1
  fi

  printf '%s\n' "$range"
  return 0
}