#!/usr/bin/env bash
# init_agent_session.sh -- unified session align entry (--grok or --claude)
#
# Usage (from host project):
#   scripts/init_agent_session.sh --grok [session-clone-path]
#   scripts/init_agent_session.sh --claude [session-clone-path]
#
# Dispatches to init_grok_session.sh or init_claude_session.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

err() { printf '[ERR]  %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: init_agent_session.sh --grok|--claude [session-clone-path]

Session align for the authorized AI git workflow. Pass exactly one agent flag:
  --grok     Grok / Cursor session clone
  --claude   Claude Code session clone

Optional session-clone-path defaults to the current git repo root.
EOF
}

AGENT=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --grok)
      [[ -z "$AGENT" ]] || err "Pass only one of --grok or --claude"
      AGENT=grok
      shift
      ;;
    --claude)
      [[ -z "$AGENT" ]] || err "Pass only one of --grok or --claude"
      AGENT=claude
      shift
      ;;
    --)
      shift
      EXTRA_ARGS+=("$@")
      break
      ;;
    -*)
      err "Unknown option: $1 (see --help)"
      ;;
    *)
      EXTRA_ARGS+=("$1")
      shift
      ;;
  esac
done

[[ -n "$AGENT" ]] || err "Required: --grok or --claude (see --help)"

dispatch() {
  local backend="$1"
  if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    exec "$backend" "${EXTRA_ARGS[@]}"
  fi
  exec "$backend"
}

case "$AGENT" in
  grok)   dispatch "${SCRIPT_DIR}/init_grok_session.sh" ;;
  claude) dispatch "${SCRIPT_DIR}/init_claude_session.sh" ;;
esac