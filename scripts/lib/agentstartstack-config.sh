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
  # source of truth for both the init scripts and nut's clone discovery (which
  # matches clones by git origin URL -- no project-specific subdir naming assumed).
  AGENT_SESSION_CLONE_PARENT="${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"

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