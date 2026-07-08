#!/usr/bin/env bash
# cli-preamble.sh -- shared preamble every consumer CLI invokes on each run.
#
# CONTRACT: this script prints shell code to STDOUT for the caller to `eval`, so
# the consumer CLI's wiring is a single, permanently static line at the top of
# main() (before command dispatch). All policy lives here, not in the consumer:
#
#   eval "$("${REPO_ROOT}/.agentstartstack/scripts/cli-preamble.sh" "$REPO_ROOT")"
#
# After the eval the caller has $AGENTSTARTSTACK_CLI_HEAD (the reproducible HEAD
# SHA to record as run provenance) and, when undo is configured, a registered
# EXIT trap that peels the auto-commit back on completion. stdout is strictly
# `KEY=val` / `trap` lines; ALL human diagnostics go to stderr; exit is always 0
# (non-fatal -- the preamble must never block the CLI). This is the eval-a-hook
# idiom (ssh-agent, direnv, dircolors); stdout is kept inert on every path.
#
# FIRST responsibility -- working-tree hygiene for reproducible provenance:
#   If the canonical repo is dirty, auto-commit the working tree so GIT HEAD
#   documents the EXACT code about to run. Stashing is deliberately NOT used (it
#   hides the running code from HEAD). Committing does not rewrite the working
#   file bytes, so a CLI that commits its own dirty source keeps executing safely.
#
# Every auto-commit carries a distinctive trailer so it is trivially greppable and
# can be discarded/squashed later:  git log --grep '^Agentstartstack-Autocommit:'
#
# Usage: cli-preamble.sh [REPO_ROOT]
#   REPO_ROOT defaults to `git rev-parse --show-toplevel` from the current dir.
#
# Env / config toggles (env wins; else read from <repo>/.agentstartstack.env):
#   AGENTSTARTSTACK_CLI_TOOL              -- label folded into the commit message.
#   AGENTSTARTSTACK_CLI_PREAMBLE=0        -- disable entirely (emit HEAD only).
#   AGENTSTARTSTACK_CLI_AUTOCOMMIT=0      -- dirty-check but do not commit; warn.
#   AGENTSTARTSTACK_CLI_AUTOCOMMIT_UNDO=1 -- arm the cli-postamble.sh EXIT trap
#                                            (peel the auto-commit back on exit).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Marker trailer stamped on every auto-commit (greppable for cleanup) and state
# file name shared with cli-postamble.sh. Keep both in sync across the pair.
AGENTSTARTSTACK_AUTOCOMMIT_TRAILER="Agentstartstack-Autocommit"
AGENTSTARTSTACK_UNDO_STATE="agentstartstack-cli-undo"

info() { printf '[INFO] %s\n' "$*" >&2; }
ok()   { printf '[OK]   %s\n' "$*" >&2; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

# Current HEAD SHA (stdout), null SHA if unresolved. Used internally via $(...).
head_sha() {
  git -C "$1" rev-parse HEAD 2>/dev/null || printf '0000000000000000000000000000000000000000\n'
}

# Emit the eval channel's HEAD assignment (always emitted, on every return path).
emit_head() { printf 'AGENTSTARTSTACK_CLI_HEAD=%s\n' "$(head_sha "$1")"; }

resolve_repo() {
  local arg="${1:-}"
  if [[ -n "$arg" ]]; then
    [[ -d "$arg" ]] || return 1
    (cd "$arg" && git rev-parse --show-toplevel 2>/dev/null) || return 1
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null || return 1
}

# Read a toggle from the environment, falling back to <repo>/.agentstartstack.env
# so persist-vs-undo (and similar policy) is configured WITHOUT editing the
# consumer CLI. Prints the resolved value; empty when unset.
toggle() {
  local repo="$1" key="$2" v="${!2:-}"
  if [[ -z "$v" && -f "${repo}/.agentstartstack.env" ]]; then
    v="$(sed -n "s/^${key}=//p" "${repo}/.agentstartstack.env" 2>/dev/null | head -n1)"
  fi
  printf '%s' "$v"
}

# True when $1 is an AGENT SESSION CLONE/WORKTREE rather than a canonical consumer
# repo. This preamble is intended ONLY for a human (or `ass`) operating on the
# canonical repo; in a clone it must be a strict no-op, because auto-committing
# there would create commits that fight session alignment (canonical always wins).
# Signals (any one is decisive):
#   - the repo lives under an AGENT_SESSION_CLONE_PARENT (~/.claude|.grok/worktrees);
#   - its .agentstartstack.env names a CANONICAL_LOCAL_REPO that is some OTHER path;
#   - an agentstartstack session-init marker sits in its git dir.
is_agent_session_clone() {
  local repo="$1" rp parents base gitdir canon
  rp="$(readlink -f "$repo" 2>/dev/null || printf '%s' "$repo")"

  parents="${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"
  local IFS=:
  for base in $parents; do
    [[ -n "$base" ]] || continue
    base="$(readlink -f "$base" 2>/dev/null || printf '%s' "$base")"
    [[ "$rp" == "$base"/* ]] && return 0
  done
  unset IFS

  if [[ -f "${repo}/.agentstartstack.env" ]]; then
    canon="$(sed -n 's/^CANONICAL_LOCAL_REPO=//p' "${repo}/.agentstartstack.env" 2>/dev/null | head -n1)"
    if [[ -n "$canon" ]]; then
      canon="$(readlink -f "$canon" 2>/dev/null || printf '%s' "$canon")"
      [[ "$canon" != "$rp" ]] && return 0
    fi
  fi

  gitdir="$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null || printf '%s/.git' "$repo")"
  [[ -f "${gitdir}/agentstartstack-session-init" ]] && return 0

  return 1
}

# Record restore-state for the undo trap: pre-commit SHA and the auto-commit SHA,
# under the repo git dir so cli-postamble.sh finds it. Then emit the EXIT-trap
# line for the caller to eval (double %q so paths with spaces round-trip safely).
arm_undo() {
  local repo="$1" pre="$2" auto="$3" gitdir post cmd
  gitdir="$(git -C "$repo" rev-parse --git-dir 2>/dev/null)" || return 0
  [[ "$gitdir" = /* ]] || gitdir="${repo}/${gitdir}"
  printf 'PRE=%s\nAUTO=%s\n' "$pre" "$auto" > "${gitdir}/${AGENTSTARTSTACK_UNDO_STATE}" 2>/dev/null || return 0

  post="${SCRIPT_DIR}/cli-postamble.sh"
  cmd="$(printf '%q %q' "$post" "$repo")"
  printf 'trap %q EXIT\n' "$cmd"
  info "cli-preamble: undo armed; auto-commit will be peeled back on command completion"
}

main() {
  local repo
  repo="$(resolve_repo "${1:-}")" || {
    warn "cli-preamble: not inside a git repo; skipping preamble"
    printf 'AGENTSTARTSTACK_CLI_HEAD=0000000000000000000000000000000000000000\n'
    return 0
  }

  # Opt-out escape hatch: no side effects, just report the current HEAD.
  if [[ "$(toggle "$repo" AGENTSTARTSTACK_CLI_PREAMBLE)" == "0" ]]; then
    emit_head "$repo"; return 0
  fi

  # Canonical-only: strict no-op inside an agent session clone (see guard above).
  if is_agent_session_clone "$repo"; then
    info "cli-preamble: agent session clone detected; skipping (canonical-only)"
    emit_head "$repo"; return 0
  fi

  # --- 1. Working-tree hygiene: dirty -> committed so HEAD documents the run ---
  if [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]]; then
    if [[ "$(toggle "$repo" AGENTSTARTSTACK_CLI_AUTOCOMMIT)" == "0" ]]; then
      warn "cli-preamble: working tree dirty and autocommit disabled; HEAD does not match the running code"
    else
      local tool ts pre msg
      tool="${AGENTSTARTSTACK_CLI_TOOL:-cli}"
      ts="$(date -Is 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"
      pre="$(head_sha "$repo")"
      msg="$(printf '%s: auto-commit working tree before run %s\n\n%s: %s %s' \
        "$tool" "$ts" "$AGENTSTARTSTACK_AUTOCOMMIT_TRAILER" "$tool" "$ts")"
      if git -C "$repo" add -A && git -C "$repo" commit -m "$msg" >/dev/null 2>&1; then
        ok "cli-preamble: auto-committed working tree -> reproducible HEAD (${tool} ${ts})"
        if [[ "$(toggle "$repo" AGENTSTARTSTACK_CLI_AUTOCOMMIT_UNDO)" == "1" ]]; then
          arm_undo "$repo" "$pre" "$(head_sha "$repo")"
        fi
      else
        warn "cli-preamble: auto-commit failed (pre-commit hook or nothing to commit?); HEAD may not match the tree"
      fi
    fi
  fi

  # --- 2. Worktree management (extension point) --------------------------------
  # Reserved: session-worktree adoption / alignment before the command runs.
  # See scripts/lib/session-clones.sh. Not yet wired -- add here when specified.

  # --- 3. Command hooks (extension point) --------------------------------------
  # Reserved: pre-command hooks common to every consumer CLI. Add here when
  # specified; keep them fast and non-fatal so the preamble never blocks the CLI.

  emit_head "$repo"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
