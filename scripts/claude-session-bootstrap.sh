#!/usr/bin/env bash
# claude-session-bootstrap.sh -- SessionStart hook entrypoint for Claude Code.
#
# Guarantees the mandated AI git workflow step 1 (session align) happens
# deterministically, without relying on the agent reading CLAUDE.md prose:
#
#   - If already inside a session clone -> emit that path as context; do nothing.
#   - Else (in the canonical repo) -> reuse the newest existing session clone
#     (safe fast-forward only, never destructive), or create+adopt a fresh one,
#     then emit its path as context so the agent works there.
#
# Contract with the harness: STDOUT carries ONLY the SessionStart additionalContext
# JSON. All tool chatter goes to STDERR (visible with `claude --debug`, never
# injected into the model context). The hook never fails the session -- any error
# degrades to "no context added".
#
# Wire it up (consumer .claude/settings.json) with install-session-start-hook.sh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/session-clones.sh
source "${SCRIPT_DIR}/lib/session-clones.sh"
# shellcheck source=lib/agentstartstack-config.sh
source "${SCRIPT_DIR}/lib/agentstartstack-config.sh"

log() { printf '[bootstrap] %s\n' "$*" >&2; }

# Where to create Claude worktrees, and guarantee that location is also searched
# for reuse. session-clones.sh only defaults AGENT_SESSION_CLONE_PARENT when unset;
# an inherited value may omit ~/.claude/worktrees (then we would create there but
# never rediscover it, spawning a clone every session). Prefer a configured
# *claude* parent, else ~/.claude/worktrees, and prepend it to the search path.
IFS=: read -r -a _parents <<< "${AGENT_SESSION_CLONE_PARENT}"
CREATE_PARENT=""
for _p in "${_parents[@]}"; do
  [[ "$_p" == *claude* ]] && { CREATE_PARENT="$_p"; break; }
done
[[ -n "$CREATE_PARENT" ]] || CREATE_PARENT="${HOME}/.claude/worktrees"
case ":${AGENT_SESSION_CLONE_PARENT}:" in
  *":${CREATE_PARENT}:"*) : ;;
  *) AGENT_SESSION_CLONE_PARENT="${CREATE_PARENT}:${AGENT_SESSION_CLONE_PARENT}" ;;
esac
export AGENT_SESSION_CLONE_PARENT

# Emit a SessionStart additionalContext payload (JSON) on stdout, then exit 0.
# $1 is the context string; backslashes, quotes, and newlines are escaped.
emit_context() {
  local msg="$1" esc
  esc=${msg//\\/\\\\}
  esc=${esc//\"/\\\"}
  esc=${esc//$'\n'/\\n}
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$esc"
  exit 0
}

# Emit nothing (valid: no context added) and exit 0. Used for any non-consumer or
# error path so a hook hiccup never blocks or noisily fails the session.
emit_nothing() { exit 0; }

# True if $1 resolves to a path under one of AGENT_SESSION_CLONE_PARENT's dirs.
_under_clone_parent() {
  local path parents base
  path="$(readlink -f "$1" 2>/dev/null)" || return 1
  [[ -n "$path" ]] || return 1
  parents="${AGENT_SESSION_CLONE_PARENT}"
  local IFS=:
  for base in $parents; do
    [[ -n "$base" ]] || continue
    base="$(readlink -f "$base" 2>/dev/null || echo "$base")"
    [[ "$path" == "$base" || "$path" == "$base"/* ]] && return 0
  done
  return 1
}

toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || emit_nothing
[[ -n "$toplevel" ]] || emit_nothing
toplevel="$(readlink -f "$toplevel")"

# Already in a session clone: confirm it, do not spawn another.
if _under_clone_parent "$toplevel"; then
  emit_context "agentstartstack: you are already in your Claude Code session clone at ${toplevel}. Work here (absolute paths); never edit the canonical repo. Run 'ass sync' from canonical to hand off."
fi

# In canonical (or an unrelated dir). Load consumer identity; a repo with no
# .agentstartstack.env (e.g. the template itself) is not a consumer -- do nothing.
agentstartstack_load_config "$toplevel" 2>/dev/null || emit_nothing
agentstartstack_apply_defaults 2>/dev/null || emit_nothing
canonical="$(readlink -f "$CANONICAL_LOCAL_REPO")"
origin="$(git -C "$canonical" remote get-url origin 2>/dev/null)" || emit_nothing
[[ -n "$origin" ]] || emit_nothing

# Reuse the newest existing session clone for this repo, if any.
clone=""
mapfile -t _clones < <(agent_session_clones_list "$origin")
if [[ ${#_clones[@]} -gt 0 ]]; then
  clone="${_clones[0]}"
  log "reusing newest session clone: ${clone}"
  # Safe fast-forward only when clean -- never hard-reset (would drop unlanded
  # commits or dirty work). ff-only cannot lose work; ignore failure (diverged/ahead).
  if [[ -z "$(git -C "$clone" status --porcelain 2>/dev/null)" ]]; then
    git -C "$clone" fetch --quiet local-sync main >&2 2>&1 || true
    if git -C "$clone" merge --ff-only local-sync/main >/dev/null 2>&1; then
      log "fast-forwarded ${clone} to canonical"
    else
      log "left ${clone} as-is (diverged/ahead or no local-sync)"
    fi
  else
    log "left ${clone} as-is (has uncommitted work)"
  fi
else
  # No clone yet: create a full clone under ~/.claude/worktrees/<project>/<id>,
  # then adopt it (normalizes origin, writes .agentstartstack.env, aligns via init).
  local_id="$(date +%s)-$$"
  parent="${CREATE_PARENT}/${PROJECT_NAME}"
  clone="${parent}/${local_id}"
  log "no session clone found; creating ${clone}"
  mkdir -p "$parent" || emit_nothing
  if ! git clone --quiet "$canonical" "$clone" >&2 2>&1; then
    log "git clone failed; no context added"
    rm -rf "$clone" 2>/dev/null || true
    emit_nothing
  fi
  if ! bash "${SCRIPT_DIR}/ass.sh" adopt --claude --canonical "$canonical" "$clone" >&2 2>&1; then
    log "ass adopt failed for ${clone}; no context added"
    emit_nothing
  fi
fi

[[ -n "$clone" && -d "$clone" ]] || emit_nothing

emit_context "agentstartstack: your Claude Code session clone is ready at ${clone}. Work there using ABSOLUTE paths -- never edit the canonical repo at ${canonical}. This is AI git workflow step 1 (session align), done for you. When the human says 'sync'/'ass', run: cd ${canonical} && ass sync."
