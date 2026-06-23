#!/usr/bin/env bash
# install-precommit-guard.sh -- install the agentstartstack pre-commit guard.
#
# The guard refuses commits while a .agentstartstack-bump watch file is pending
# (see agentstartstack/workflow.md), then chains to the repo's tracked
# .githooks/pre-commit so shellcheck and other checks still run. It lives under
# .git/ so it survives reset --hard + clean -fd and never dirties the tree.
#
# Single source of truth: called by both init_claude_session.sh /
# init_grok_session.sh and install-githooks.sh, so running either installs the
# same guard -- the two cannot diverge and re-running never silently drops it.
#
# Usage: install-precommit-guard.sh [repo-root]   (default: git toplevel)
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel)}"
ROOT="$(cd "$ROOT" && pwd)"

GUARD_DIR="${ROOT}/.git/agentstartstack-hooks"
mkdir -p "$GUARD_DIR"

cat > "${GUARD_DIR}/pre-commit" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
if [[ -f "${ROOT}/.agentstartstack-bump" ]]; then
  echo "pre-commit: .agentstartstack-bump is pending -- read the producer commits and" >&2
  echo "reconcile this consumer, then commit and remove the flag. See workflow.md:" >&2
  echo "the '.agentstartstack-bump watch file' section." >&2
  exit 1
fi
# Chain to the repo's tracked hook (shellcheck etc.) if present.
if [[ -x "${ROOT}/.githooks/pre-commit" ]]; then
  exec "${ROOT}/.githooks/pre-commit"
fi
HOOK

chmod +x "${GUARD_DIR}/pre-commit"
git -C "$ROOT" config core.hooksPath .git/agentstartstack-hooks
