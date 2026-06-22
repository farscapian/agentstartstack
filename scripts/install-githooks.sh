#!/usr/bin/env bash
# Install git hooks (pre-commit: shellcheck staged .sh files).
set -euo pipefail

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

git -C "$GIT_ROOT" config core.hooksPath .githooks
echo "Git hooks installed (pre-commit: shellcheck staged .sh files)"