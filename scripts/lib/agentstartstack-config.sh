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
  SYNC_REPO="${SYNC_REPO:-}"
  ORIGIN_URL="${ORIGIN_URL:-}"
  ACTIVE_GUARD_PGREP="${ACTIVE_GUARD_PGREP:-}"

  if [[ -z "$PROJECT_NAME" ]]; then
    echo "[ERR]  PROJECT_NAME not set in .agentstartstack.env" >&2
    return 1
  fi

  if [[ -z "$SYNC_REPO" ]]; then
    if [[ -d "${HOME}/Sync/mini_projects/${PROJECT_NAME}/.git" ]]; then
      SYNC_REPO="${HOME}/Sync/mini_projects/${PROJECT_NAME}"
    elif [[ -d "${HOME}/Sync/${PROJECT_NAME}/.git" ]]; then
      SYNC_REPO="${HOME}/Sync/${PROJECT_NAME}"
    fi
  fi

  SYNC_REPO="$(cd "$SYNC_REPO" 2>/dev/null && pwd)" || {
    echo "[ERR]  SYNC_REPO not found: ${SYNC_REPO:-<unset>}" >&2
    return 1
  }

  GROK_PARENT="${GROK_PARENT:-${HOME}/.grok/worktrees/mini-projects-${PROJECT_NAME}}"
  CLAUDE_PARENT="${CLAUDE_PARENT:-${HOME}/.claude/worktrees/mini-projects-${PROJECT_NAME}}"

  return 0
}

# Set GENERIC_GUIDANCE_DIR and PROJECT_GUIDANCE_DIR from host repo layout.
agentstartstack_resolve_guidance_paths() {
  local root="${1:-${AGENTSTARTSTACK_HOST_ROOT:-}}"

  [[ -n "$root" ]] || return 1

  if [[ -d "${root}/.agentstartstack/agentstartstack" ]]; then
    GENERIC_GUIDANCE_DIR=".agentstartstack/agentstartstack"
    PROJECT_GUIDANCE_DIR="agentstartstack"
  elif [[ -d "${root}/agentstartstack/agentstartstack" ]]; then
    GENERIC_GUIDANCE_DIR="agentstartstack/agentstartstack"
    PROJECT_GUIDANCE_DIR="agentstartstack"
  elif [[ -d "${root}/agentstartstack" ]]; then
    GENERIC_GUIDANCE_DIR="agentstartstack"
    PROJECT_GUIDANCE_DIR="agentstartstack"
  else
    echo "[ERR]  No agentstartstack guidance directory found under: $root" >&2
    return 1
  fi

  return 0
}