#!/usr/bin/env bash
# install-session-start-hook.sh -- wire the Claude Code SessionStart bootstrap
# hook into a consumer's .claude/settings.json (idempotent).
#
# The hook runs scripts/claude-session-bootstrap.sh at every session start, which
# deterministically performs AI git workflow step 1 (create/reuse + align a
# session clone) and injects the clone path as context -- so an agent works in its
# clone from the first message without relying on reading CLAUDE.md prose.
#
# Usage: install-session-start-hook.sh [consumer-repo-root]
#   Defaults to the current git toplevel. Run it from (or point it at) the
#   consumer repo -- in an agent session, the consumer session clone -- so the
#   committed .claude/settings.json flows to canonical via ass.
#
# Requires jq. Safe to re-run: a matching SessionStart hook is not duplicated.

set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
err()  { printf '[ERR]  %s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || err "jq is required (install jq, then re-run)."

ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[[ -n "$ROOT" ]] || err "Not inside a git repo; pass the consumer repo root."
ROOT="$(cd "$ROOT" && pwd)"
[[ -d "${ROOT}/.agentstartstack" ]] || err "No .agentstartstack submodule at ${ROOT}; is this a consumer repo?"

SETTINGS_DIR="${ROOT}/.claude"
SETTINGS="${SETTINGS_DIR}/settings.json"
mkdir -p "$SETTINGS_DIR"
[[ -f "$SETTINGS" ]] || printf '{}\n' > "$SETTINGS"

# Resolve the bootstrap via CLAUDE_PROJECT_DIR (set by the harness for hooks),
# falling back to the git toplevel; no-op if the submodule is not initialized.
CMD='f="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null)}/.agentstartstack/scripts/claude-session-bootstrap.sh"; [ -x "$f" ] && bash "$f" || true'

if jq -e '[.hooks.SessionStart[]?.hooks[]?.command // empty] | any(test("claude-session-bootstrap\\.sh"))' \
     "$SETTINGS" >/dev/null 2>&1; then
  ok "SessionStart bootstrap hook already present in ${SETTINGS}"
  exit 0
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/asss-settings.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
jq --arg cmd "$CMD" '
  .hooks = (.hooks // {})
  | .hooks.SessionStart = (.hooks.SessionStart // [])
  | .hooks.SessionStart += [ { "hooks": [ { "type": "command", "command": $cmd } ] } ]
' "$SETTINGS" > "$tmp" || err "Failed to update ${SETTINGS} (invalid JSON?)"

# Validate the result parses and the hook is present before replacing.
jq -e '[.hooks.SessionStart[]?.hooks[]?.command // empty] | any(test("claude-session-bootstrap\\.sh"))' \
   "$tmp" >/dev/null || err "Post-write validation failed; left ${SETTINGS} unchanged."
cat "$tmp" > "$SETTINGS"

ok "Added SessionStart bootstrap hook to ${SETTINGS}"
info "New Claude Code sessions in this repo now auto-create/align a session clone."
info "Review or disable it anytime via the /hooks menu."
