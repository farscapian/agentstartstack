#!/usr/bin/env bash
# install-precommit-guard.sh -- install the agentstartstack pre-commit reminder.
#
# When a .agentstartstack-bump watch file is pending (see
# agentstartstack/workflow.md) the hook prints a reminder to reconcile the bump
# but does NOT block the commit -- the bump is handled eventually, not treated as
# a blocker to a consumer's own work. It then chains to the repo's tracked
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
  # Reminder only -- never block the commit. The bump is handled eventually, not
  # a blocker to this consumer's own work.
  echo "pre-commit: .agentstartstack-bump is still pending (commit not blocked) --" >&2
  echo "read the producer commits and reconcile this consumer, then remove the flag." >&2
  echo "See workflow.md: the '.agentstartstack-bump watch file' section." >&2
fi
# Chain to the repo's tracked hook (shellcheck etc.) if present.
if [[ -x "${ROOT}/.githooks/pre-commit" ]]; then
  exec "${ROOT}/.githooks/pre-commit"
fi
HOOK

chmod +x "${GUARD_DIR}/pre-commit"
git -C "$ROOT" config core.hooksPath .git/agentstartstack-hooks
