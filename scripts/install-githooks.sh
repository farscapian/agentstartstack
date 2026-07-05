#!/usr/bin/env bash
# Install git hooks (pre-commit: .agentstartstack-bump reminder + shellcheck staged .sh files).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not a git repository" >&2
  exit 1
}

if [[ -f "${GIT_ROOT}/.agentstartstack/.githooks/pre-commit" ]]; then
  chmod +x \
    "${GIT_ROOT}/.githooks/pre-commit" \
    "${GIT_ROOT}/scripts/shellcheck-staged.sh" \
    "${GIT_ROOT}/.agentstartstack/scripts/shellcheck-staged.sh"
elif [[ -f "${GIT_ROOT}/agentstartstack/.githooks/pre-commit" ]]; then
  chmod +x \
    "${GIT_ROOT}/.githooks/pre-commit" \
    "${GIT_ROOT}/scripts/shellcheck-staged.sh" \
    "${GIT_ROOT}/agentstartstack/scripts/shellcheck-staged.sh"
else
  chmod +x \
    "${GIT_ROOT}/.githooks/pre-commit" \
    "${GIT_ROOT}/scripts/shellcheck-staged.sh"
fi

# Install the agentstartstack pre-commit reminder. It points core.hooksPath at
# .git/agentstartstack-hooks and chains to .githooks/pre-commit (the shellcheck
# hook chmod'd above), so the reminder and shellcheck both run. Shared with the
# init scripts so re-running either keeps it installed -- they cannot diverge.
"${SCRIPT_DIR}/install-precommit-guard.sh" "$GIT_ROOT"
echo "Git hooks installed (pre-commit: .agentstartstack-bump reminder + shellcheck staged .sh files)"