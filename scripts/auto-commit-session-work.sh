#!/usr/bin/env bash
# auto-commit-session-work.sh -- commit all uncommitted work in a session clone.
#
# Wired into init_*_session.sh after session align. Prevents session work from
# living only in the working tree (and being lost on accidental hard-reset).
#
# Usage: auto-commit-session-work.sh [session-clone-path]

set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }

resolve_repo() {
  local arg="${1:-}"
  if [[ -n "$arg" ]]; then
    [[ -d "$arg" ]] || return 1
    (cd "$arg" && pwd)
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null || return 1
}

REPO="$(resolve_repo "${1:-}")" || {
  printf '[WARN] auto-commit-session-work: not in a git repo; skipping\n' >&2
  exit 0
}

cd "$REPO"
git rev-parse --is-inside-work-tree &>/dev/null || exit 0

if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
  info "Session clone clean; nothing to auto-commit"
  exit 0
fi

msg="ass: auto-commit session work $(date -Is 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"
git add -A
if git commit -m "$msg"; then
  ok "Auto-committed session clone work: ${msg}"
else
  printf '[WARN] auto-commit-session-work: commit failed (hooks or empty after add?)\n' >&2
  exit 0
fi