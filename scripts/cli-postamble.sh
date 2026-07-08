#!/usr/bin/env bash
# cli-postamble.sh -- EXIT-trap companion to cli-preamble.sh (undo mode only).
#
# A consumer CLI that ran cli-preamble.sh with AGENTSTARTSTACK_CLI_AUTOCOMMIT_UNDO=1
# registers this as an EXIT trap:
#
#   trap '.agentstartstack/scripts/cli-postamble.sh' EXIT
#
# When the command finishes it peels the auto-commit back with a soft reset,
# restoring the working tree to the uncommitted state the user had before the run
# (stash/pop semantics done through a commit). No-op unless the preamble left
# restore-state, so it is safe to register unconditionally.
#
# Safety: only resets when HEAD is still exactly the auto-commit -- if the CLI
# made further commits on top, it leaves history alone (and warns), never folding
# real commits back into the working tree.
#
# Usage: cli-postamble.sh [REPO_ROOT]   (REPO_ROOT defaults to the current repo)
# Always exits 0: an EXIT trap must not mask the command's own status.

set -uo pipefail

AGENTSTARTSTACK_UNDO_STATE="agentstartstack-cli-undo"

warn() { printf '[WARN] %s\n' "$*" >&2; }
info() { printf '[INFO] %s\n' "$*" >&2; }

main() {
  local repo gitdir state pre auto head
  repo="$(cd "${1:-.}" && git rev-parse --show-toplevel 2>/dev/null)" || return 0
  gitdir="$(git -C "$repo" rev-parse --git-dir 2>/dev/null)" || return 0
  [[ "$gitdir" = /* ]] || gitdir="${repo}/${gitdir}"
  state="${gitdir}/${AGENTSTARTSTACK_UNDO_STATE}"

  [[ -f "$state" ]] || return 0   # no undo armed; nothing to do

  pre="$(sed -n 's/^PRE=//p' "$state" | head -n1)"
  auto="$(sed -n 's/^AUTO=//p' "$state" | head -n1)"
  rm -f "$state"

  [[ -n "$pre" && -n "$auto" ]] || return 0

  head="$(git -C "$repo" rev-parse HEAD 2>/dev/null)" || return 0
  if [[ "$head" != "$auto" ]]; then
    warn "cli-postamble: HEAD moved past the auto-commit; leaving history intact (undo skipped)"
    return 0
  fi

  if git -C "$repo" reset --soft "$pre" >/dev/null 2>&1; then
    info "cli-postamble: auto-commit peeled back; working tree restored to pre-run state"
  else
    warn "cli-postamble: soft reset to ${pre} failed; auto-commit left in place"
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
