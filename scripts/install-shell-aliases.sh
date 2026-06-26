#!/usr/bin/env bash
# install-shell-aliases.sh -- idempotently install the nut/nutup shell aliases.
#
# Writes a managed block into ~/.bash_aliases that **sources** the canonical
# lib/nut-aliases.sh from a persistent checkout (so all nut/nutup/nutupyall/dropit
# logic lives in the repo exclusively -- the shell only references it), and ensures
# ~/.bashrc sources ~/.bash_aliases. The sourced path is resolved to the
# agentstartstack canonical repo, never a session clone (nutup trim deletes those).
# Re-running replaces the managed block in place, so it is safe to call every
# session -- both init_claude_session.sh and init_grok_session.sh call it, and the
# human can run it directly (see the CONSUMER-ACTION in the bump that updates it).
#
# Machine-global and config-free: it needs no .agentstartstack.env. It never
# sources your shell for you (a child process cannot) -- it prints the command.
#
# Usage: install-shell-aliases.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/lib/nut-aliases.sh"

BEGIN_MARK="# >>> agentstartstack nut aliases >>>"
END_MARK="# <<< agentstartstack nut aliases <<<"

ALIASES_FILE="${HOME}/.bash_aliases"
BASHRC="${HOME}/.bashrc"

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERR]  %s\n' "$*" >&2; exit 1; }

[[ -f "$SRC" ]] || err "Canonical aliases not found: $SRC"

# Compute a sensible default for AGENTSTARTSTACK_PROJECT_ROOTS from where this
# repo actually lives -- the parent of the outer repo (the consumer superproject
# if installed from a submodule, else this repo itself). This keeps any personal
# path OUT of the tracked template: the value is derived on the user's machine at
# install time, and the user can still override it via the environment.
detect_default_roots() {
  local super top
  super="$(git -C "$SCRIPT_DIR" rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  if [[ -n "$super" ]]; then
    dirname "$(cd "$super" && pwd)"
    return 0
  fi
  top="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$top" ]]; then
    dirname "$(cd "$top" && pwd)"
    return 0
  fi
  return 1
}
DEFAULT_ROOTS="$(detect_default_roots || true)"

# Resolve a STABLE path to nut-aliases.sh for ~/.bash_aliases to source. It must
# NOT be a session clone (nutup trim deletes those, which would break the source
# line), so prefer the agentstartstack canonical checkout under the project roots;
# fall back to SCRIPT_DIR's own copy only if that is itself not under a clone parent.
resolve_stable_src() {
  local roots r cand parents base in_clone=0
  roots="${AGENTSTARTSTACK_PROJECT_ROOTS:-$DEFAULT_ROOTS}"
  local IFS=:
  for r in $roots; do
    [[ -n "$r" ]] || continue
    cand="${r}/agentstartstack/scripts/lib/nut-aliases.sh"
    [[ -f "$cand" ]] && { readlink -f "$cand"; return 0; }
  done

  parents="${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"
  for base in $parents; do
    [[ -n "$base" ]] || continue
    [[ "$SCRIPT_DIR" == "$base"/* ]] && { in_clone=1; break; }
  done
  [[ "$in_clone" == 0 ]] && { readlink -f "$SRC"; return 0; }
  return 1
}

STABLE_SRC="$(resolve_stable_src || true)"
[[ -n "$STABLE_SRC" ]] || err "Cannot resolve a non-clone nut-aliases.sh to source. Run the installer from the agentstartstack canonical repo (or a consumer canonical), or set AGENTSTARTSTACK_PROJECT_ROOTS to the dir holding your agentstartstack checkout."
bash -n "$STABLE_SRC" 2>/dev/null || warn "Source file has a syntax error: ${STABLE_SRC} (new shells may fail to load aliases)"

# Build the managed block: markers, a "do not edit" note, an overridable default
# for the project-roots search path, then a guarded source of the canonical
# nut-aliases.sh. A trap cleans the tempfile on any exit.
tmp="$(mktemp "${TMPDIR:-/tmp}/nut-aliases.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

{
  printf '%s\n' "$BEGIN_MARK"
  printf '%s\n' "# Managed by agentstartstack scripts/install-shell-aliases.sh -- do not edit."
  printf '%s\n' "# This sources the canonical nut-aliases.sh from the agentstartstack repo;"
  printf '%s\n' "# all nut/nutup/dropit logic lives there. Edit it there, not here."
  if [[ -n "$DEFAULT_ROOTS" ]]; then
    printf '%s\n' "# Default project-roots search path (computed at install time). Override by"
    printf '%s\n' "# exporting AGENTSTARTSTACK_PROJECT_ROOTS before this file is sourced."
    printf ': "${AGENTSTARTSTACK_PROJECT_ROOTS:=%s}"\n' "$DEFAULT_ROOTS"
    printf '%s\n' "export AGENTSTARTSTACK_PROJECT_ROOTS"
  fi
  printf '[ -f "%s" ] && . "%s"\n' "$STABLE_SRC" "$STABLE_SRC"
  printf '%s\n' "$END_MARK"
} > "$tmp"

# If the file already has a managed block, replace it in place; otherwise append.
# awk does the splice so we never depend on sed -i portability.
if [[ -f "$ALIASES_FILE" ]] && grep -qF "$BEGIN_MARK" "$ALIASES_FILE"; then
  merged="$(mktemp "${TMPDIR:-/tmp}/nut-aliases-merged.XXXXXX")"
  trap 'rm -f "$tmp" "$merged"' EXIT
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v blockfile="$tmp" '
    $0 == b { while ((getline line < blockfile) > 0) print line; close(blockfile); skip=1; next }
    $0 == e { skip=0; next }
    skip != 1 { print }
  ' "$ALIASES_FILE" > "$merged"
  cat "$merged" > "$ALIASES_FILE"
  rm -f "$merged"
  ok "Updated managed nut-aliases block in ${ALIASES_FILE}"
else
  # Preserve any existing unmanaged content; add a separating newline if needed.
  if [[ -s "$ALIASES_FILE" ]]; then
    printf '\n' >> "$ALIASES_FILE"
  fi
  cat "$tmp" >> "$ALIASES_FILE"
  ok "Added managed nut-aliases block to ${ALIASES_FILE}"
fi

# Warn (do not auto-edit) if legacy unmanaged definitions linger outside the
# block -- e.g. a hand-maintained copy from before this installer existed.
if awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { skip=1; next } $0 == e { skip=0; next }
    skip != 1 && /(^|[^_[:alnum:]])(nutup|nut)[[:space:]]*\(\)/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$ALIASES_FILE"; then
  warn "Legacy unmanaged nut/nutup definitions remain in ${ALIASES_FILE} outside the"
  warn "  managed block. They now shadow nothing useful -- delete them so only the"
  warn "  managed block defines these functions."
fi

# Ensure ~/.bashrc sources ~/.bash_aliases (some distros do this already; add a
# guarded line within our own marker if no sourcing of .bash_aliases is present).
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
info "Done. Load the updated aliases into your current shell with:"
info "  source ~/.bashrc      # or: source ~/.bash_aliases"
