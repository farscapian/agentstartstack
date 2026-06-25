#!/usr/bin/env bash
# record-consumer-action-seen.sh -- update the consumer CONSUMER-ACTION watermark.
#
# Run from a consumer repo root after performing every CONSUMER-ACTION in the
# producer delta OLD..NEW (see agentstartstack/workflow.md).
#
# Usage:
#   scripts/record-consumer-action-seen.sh OLD_SHA NEW_SHA
#   .agentstartstack/scripts/record-consumer-action-seen.sh OLD_SHA NEW_SHA

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/agentstartstack-config.sh
source "${SCRIPT_DIR}/lib/agentstartstack-config.sh"

usage() {
  cat <<'EOF'
Usage: record-consumer-action-seen.sh OLD_SHA NEW_SHA

Updates .agentstartstack-action-seen to the latest producer commit in
OLD_SHA..NEW_SHA whose message carries CONSUMER-ACTION:. No-op when the
delta is action-free. Run from the consumer repo root after reconciling
the bump (see workflow.md).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

OLD="${1:-}"
NEW="${2:-}"
[[ -n "$OLD" && -n "$NEW" ]] || { usage >&2; exit 1; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "[ERR]  Not inside a git repo." >&2; exit 1; }

if agentstartstack_record_action_seen_from_delta "$REPO_ROOT" "$OLD" "$NEW"; then
  if latest=$(agentstartstack_read_action_seen "$REPO_ROOT" 2>/dev/null); then
    printf '[OK]   .agentstartstack-action-seen -> %s\n' "$latest"
  else
    printf '[OK]   delta %s..%s had no CONSUMER-ACTION commits; watermark unchanged\n' "$OLD" "$NEW"
  fi
else
  echo "[ERR]  .agentstartstack submodule not found under ${REPO_ROOT}" >&2
  exit 1
fi