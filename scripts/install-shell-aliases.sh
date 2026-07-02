#!/usr/bin/env bash
# install-shell-aliases.sh -- idempotently install the thin ass() shell wrapper.
#
# Writes a managed block into ~/.bash_aliases that defines ass() -> bash scripts/ass.sh.
# All command logic lives in the repo (ass.sh + lib/ass-aliases.sh). Re-running replaces
# the managed block in place. Both init_*_session.sh call this; humans can run it directly.
#
# Machine-global and config-free: needs no .agentstartstack.env.
#
# Usage: install-shell-aliases.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/session-clones.sh
source "${SCRIPT_DIR}/lib/session-clones.sh"
ASS_CLI="${SCRIPT_DIR}/ass.sh"

BEGIN_MARK="# >>> agentstartstack ass aliases >>>"
END_MARK="# <<< agentstartstack ass aliases <<<"

ALIASES_FILE="${HOME}/.bash_aliases"
BASHRC="${HOME}/.bashrc"

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERR]  %s\n' "$*" >&2; exit 1; }

[[ -f "$ASS_CLI" ]] || err "ass CLI not found: $ASS_CLI"

_under_session_clone_parent() {
  local path="$1" parents base
  [[ -n "$path" ]] || return 1
  path="$(readlink -f "$path" 2>/dev/null || echo "$path")"
  parents="${AGENT_SESSION_CLONE_PARENT}"
  local IFS=:
  for base in $parents; do
    [[ -n "$base" ]] || continue
    base="$(readlink -f "$base" 2>/dev/null || echo "$base")"
    [[ "$path" == "$base" || "$path" == "$base"/* ]] && return 0
  done
  return 1
}

_project_roots_valid() {
  local roots="$1" r
  [[ -n "$roots" ]] || return 1
  local IFS=:
  for r in $roots; do
    [[ -n "$r" ]] || continue
    _under_session_clone_parent "$r" && return 1
  done
  return 0
}

detect_default_roots() {
  local super top roots canonical
  super="$(git -C "$SCRIPT_DIR" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [[ -n "$super" ]]; then
    roots="$(dirname "$(cd "$super" && pwd)")"
    _under_session_clone_parent "$roots" || { printf '%s\n' "$roots"; return 0; }
  fi
  top="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$top" ]]; then
    roots="$(dirname "$(cd "$top" && pwd)")"
    if ! _under_session_clone_parent "$roots"; then
      printf '%s\n' "$roots"
      return 0
    fi
    canonical=$(git -C "$top" remote get-url local-sync 2>/dev/null || true)
    if [[ -n "$canonical" && -d "$canonical" ]]; then
      roots="$(dirname "$(readlink -f "$canonical")")"
      _under_session_clone_parent "$roots" || { printf '%s\n' "$roots"; return 0; }
    fi
  fi
  return 1
}

DEFAULT_ROOTS="$(detect_default_roots || true)"
if [[ -n "$DEFAULT_ROOTS" ]] && ! _project_roots_valid "$DEFAULT_ROOTS"; then
  warn "Computed AGENTSTARTSTACK_PROJECT_ROOTS is under a session-clone parent -- ignoring: ${DEFAULT_ROOTS}"
  DEFAULT_ROOTS=""
fi
if [[ -z "$DEFAULT_ROOTS" && -n "${AGENTSTARTSTACK_PROJECT_ROOTS:-}" ]] \
   && _project_roots_valid "${AGENTSTARTSTACK_PROJECT_ROOTS}"; then
  DEFAULT_ROOTS="${AGENTSTARTSTACK_PROJECT_ROOTS}"
fi

resolve_ass_cli() {
  local roots r cand parents base in_clone=0
  roots="${AGENTSTARTSTACK_PROJECT_ROOTS:-$DEFAULT_ROOTS}"
  local IFS=:
  for r in $roots; do
    [[ -n "$r" ]] || continue
    cand="${r}/agentstartstack/scripts/ass.sh"
    [[ -f "$cand" ]] && { readlink -f "$cand"; return 0; }
  done
  parents="${AGENT_SESSION_CLONE_PARENT}"
  for base in $parents; do
    [[ -n "$base" ]] || continue
    [[ "$SCRIPT_DIR" == "$base"/* ]] && { in_clone=1; break; }
  done
  [[ "$in_clone" == 0 ]] && { readlink -f "$ASS_CLI"; return 0; }
  return 1
}

ASS_CLI_PATH="$(resolve_ass_cli || true)"
[[ -n "$ASS_CLI_PATH" ]] || err "Cannot resolve ass.sh from a non-clone checkout. Run from canonical agentstartstack or set AGENTSTARTSTACK_PROJECT_ROOTS."

tmp="$(mktemp "${TMPDIR:-/tmp}/ass-cli.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

{
  printf '%s\n' "$BEGIN_MARK"
  printf '%s\n' "# Managed by agentstartstack scripts/install-shell-aliases.sh -- do not edit."
  printf '%s\n' "# Thin wrapper: ass() -> bash scripts/ass.sh (all logic in the repo)."
  if [[ -n "$DEFAULT_ROOTS" ]] && _project_roots_valid "$DEFAULT_ROOTS"; then
    printf '%s\n' "# Default project-roots search path (computed at install time)."
    printf ': "${AGENTSTARTSTACK_PROJECT_ROOTS:=%s}"\n' "$DEFAULT_ROOTS"
    printf '%s\n' "export AGENTSTARTSTACK_PROJECT_ROOTS"
  fi
  printf '%s\n' ": \"\${AGENTSTARTSTACK_ASS_CLI:=$ASS_CLI_PATH}\""
  printf '%s\n' "ass() { bash \"\${AGENTSTARTSTACK_ASS_CLI}\" \"\$@\"; }"
  printf '%s\n' "# 'face down ass up' -> ass up, then ass publish (thin wrapper)."
  printf '%s\n' "face() { bash \"\${AGENTSTARTSTACK_ASS_CLI}\" face \"\$@\"; }"
  printf '%s\n' "$END_MARK"
} > "$tmp"

if [[ -f "$ALIASES_FILE" ]] && grep -qF "$BEGIN_MARK" "$ALIASES_FILE"; then
  merged="$(mktemp "${TMPDIR:-/tmp}/ass-cli-merged.XXXXXX")"
  trap 'rm -f "$tmp" "$merged"' EXIT
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v blockfile="$tmp" '
    $0 == b { while ((getline line < blockfile) > 0) print line; close(blockfile); skip=1; next }
    $0 == e { skip=0; next }
    skip != 1 { print }
  ' "$ALIASES_FILE" > "$merged"
  cat "$merged" > "$ALIASES_FILE"
  rm -f "$merged"
  ok "Updated managed ass block in ${ALIASES_FILE}"
else
  [[ -s "$ALIASES_FILE" ]] && printf '\n' >> "$ALIASES_FILE"
  cat "$tmp" >> "$ALIASES_FILE"
  ok "Added managed ass block to ${ALIASES_FILE}"
fi

if awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { skip=1; next } $0 == e { skip=0; next }
    skip != 1 && /(^|[^_[:alnum:]])(assup|assitup)[[:space:]]*\(\)/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$ALIASES_FILE"; then
  warn "Legacy assup wrappers remain outside the managed block in ${ALIASES_FILE}"
  warn "  Delete them so only ass() is defined."
fi

SRC_LINE='[ -f ~/.bash_aliases ] && . ~/.bash_aliases'
if [[ -f "$BASHRC" ]] && grep -qE '(^|[^#]).*\.bash_aliases' "$BASHRC"; then
  info "${BASHRC} already sources ~/.bash_aliases"
else
  {
    printf '%s\n' "$BEGIN_MARK"
    printf '%s\n' "$SRC_LINE"
    printf '%s\n' "$END_MARK"
  } >> "$BASHRC"
  ok "Added ~/.bash_aliases sourcing to ${BASHRC}"
fi

echo ""
info "Done. Load the updated alias with:"
info "  source ~/.bashrc"