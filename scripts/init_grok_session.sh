#!/bin/bash
# init_grok_session.sh -- Grok session sync (AI git workflow step 1) and agent tips
#
# Usage (from host project):
#   scripts/init_grok_session.sh [session-clone-path]
#
# Requires .agentstartstack.env at the host project root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTSTARTSTACK_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/agentstartstack-config.sh
source "${SCRIPT_DIR}/lib/agentstartstack-config.sh"

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
err()  { printf '[ERR]  %s\n' "$*" >&2; exit 1; }

print_hyperlink() {
  local url="$1"
  local label="${2:-$url}"
  printf '\033]8;;%s\033\\%s\033]8;;\033\\' "$url" "$label"
}

usage() {
  cat <<'EOF'
Usage: init_grok_session.sh [session-clone-path]

Session align for the authorized AI git workflow: aligns a Grok/Cursor session
clone with the canonical local repo and prints reminders for efficient agent use.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

resolve_repo_root() {
  local arg="${1:-}"
  if [[ -n "$arg" ]]; then
    [[ -d "$arg" ]] || err "Session path not found: $arg"
    (cd "$arg" && pwd)
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null || true
}

REPO_ROOT="$(resolve_repo_root "${1:-}")"
[[ -n "$REPO_ROOT" ]] || err "Not inside a git repo. Pass the session clone path as an argument."

agentstartstack_load_config "$REPO_ROOT" || err "Missing .agentstartstack.env (run add-to-project.sh)"
agentstartstack_apply_defaults || exit 1
agentstartstack_resolve_guidance_paths "$REPO_ROOT" || err "Cannot resolve guidance paths"

if [[ "$(readlink -f "$REPO_ROOT")" == "$(readlink -f "$SYNC_REPO")" ]]; then
  warn "Current directory is the canonical local repo, not a Grok session clone."
  warn "Init is intended for ${GROK_PARENT}/<session-id>/"
  read -r -p "Continue anyway? [y/N] " confirm </dev/tty
  [[ "${confirm,,}" == "y" || "${confirm,,}" == "yes" ]] || exit 0
fi

cd "$REPO_ROOT"
git rev-parse --is-inside-work-tree &>/dev/null || err "Not a git work tree: $REPO_ROOT"

info "Session clone: $REPO_ROOT"
info "Canonical:     $SYNC_REPO"
info "Project:       ${DISPLAY_NAME} (${PROJECT_NAME})"
echo ""

# Re-running init re-aligns via a hard reset + clean, which discards uncommitted
# work. If the session clone is dirty, confirm before destroying it (a fresh
# clone is clean, so first-run init never prompts).
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  warn "Session clone has uncommitted changes; re-aligning will HARD RESET and discard them:"
  git status --short >&2
  read -r -p "Discard and re-align? [y/N] " confirm </dev/tty
  if [[ "${confirm,,}" != "y" && "${confirm,,}" != "yes" ]]; then
    info "Aborted; clone left as-is."
    exit 0
  fi
fi

info "Session align: fetching local-sync/main and resetting..."
if git remote get-url local-sync &>/dev/null; then
  git remote set-url local-sync "$SYNC_REPO"
else
  git remote add local-sync "$SYNC_REPO"
fi

git fetch local-sync main
git reset --hard local-sync/main
git clean -fd
if [[ -f .gitmodules ]]; then
  git submodule update --init --recursive
fi

# Harden origin to fetch-only: agents hand off via the local-sync remote and must
# never push to origin. Disabling the push URL makes that structural, not just
# policy. The fetch URL stays intact so nut can still match this clone to the
# canonical local repo by origin URL.
if git remote get-url origin &>/dev/null; then
  git remote set-url --push origin DISABLED
fi

# Surface a pending agentstartstack bump dropped by nutupyall (see workflow.md).
if [[ -f "${REPO_ROOT}/.agentstartstack-bump" ]]; then
  warn "Pending agentstartstack bump: $(head -1 "${REPO_ROOT}/.agentstartstack-bump")"
  warn "  Before your next commit: git submodule update --init --recursive --remote .agentstartstack && git add .agentstartstack && rm .agentstartstack-bump"
fi

# Install a pre-commit guard that blocks commits while a .agentstartstack-bump
# watch file is pending, then chains to the repo's shellcheck hook. Lives under
# .git/ so it survives reset --hard + clean -fd and never dirties the tree.
GUARD_DIR="${REPO_ROOT}/.git/agentstartstack-hooks"
mkdir -p "$GUARD_DIR"
cat > "${GUARD_DIR}/pre-commit" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
if [[ -f "${ROOT}/.agentstartstack-bump" ]]; then
  echo "pre-commit: .agentstartstack-bump is pending in this clone -- apply it first:" >&2
  echo "  git submodule update --init --recursive --remote .agentstartstack" >&2
  echo "  git add .agentstartstack && rm .agentstartstack-bump" >&2
  exit 1
fi
if [[ -x "${ROOT}/.githooks/pre-commit" ]]; then
  exec "${ROOT}/.githooks/pre-commit"
fi
HOOK
chmod +x "${GUARD_DIR}/pre-commit"
git config core.hooksPath .git/agentstartstack-hooks
info "Pre-commit guard active (blocks commits while .agentstartstack-bump pending; chains to shellcheck)."

COMMIT="$(git log -1 --oneline)"
BRANCH="$(git branch --show-current)"
WORKFLOW_MD="${REPO_ROOT}/${GENERIC_GUIDANCE_DIR}/workflow.md"
WORKFLOW_FILE_URL="file://${WORKFLOW_MD}"

ok "Aligned to ${BRANCH} @ ${COMMIT}"
printf '[INFO] Workflow guide: '
print_hyperlink "$WORKFLOW_FILE_URL" "${GENERIC_GUIDANCE_DIR}/workflow.md"
printf '\n'
echo ""

GUARD_TIP=""
if [[ -n "$ACTIVE_GUARD_PGREP" ]]; then
  GUARD_TIP="pgrep -af '${ACTIVE_GUARD_PGREP}'"
else
  GUARD_TIP="# see ACTIVE_GUARD_PGREP in .agentstartstack.env"
fi

cat <<EOF
================================================================================
Using Grok / Cursor agents efficiently (${DISPLAY_NAME})
================================================================================

AI GIT WORKFLOW (authorized)
  1. Session align -- init_grok_session.sh once per session (you just ran this)
  2. Handoff       -- human runs nut (never git push origin from agents)

GUIDANCE LOCATIONS
  Generic:  ${GENERIC_GUIDANCE_DIR}/  (workflow, nut, conventions, security)
  Project:  ${PROJECT_GUIDANCE_DIR}/   (CLI, architecture, gotchas)

FIRST MESSAGE (copy/paste template below)
  - Say you ran init_grok_session.sh (session align complete).
  - State your task in one sentence.
  - Name 1-3 guidance files to read (not all of them, not CLAUDE.md in full).

WHAT TO READ (pick 1-3)
  Git / session / handoff     -> ${GENERIC_GUIDANCE_DIR}/workflow.md, nut.md
  New shell script            -> ${GENERIC_GUIDANCE_DIR}/conventions.md, code-quality.md
  Secrets / env               -> ${GENERIC_GUIDANCE_DIR}/security.md
  Terminal copy/paste         -> ${GENERIC_GUIDANCE_DIR}/terminal.md
  Project-specific tasks      -> ${PROJECT_GUIDANCE_DIR}/<topic>.md per CLAUDE.md index

  CLAUDE.md is an index only. Do not ask the agent to read all guidance files.

TOKEN TIPS
  - Session align once per session (this script), not before every task.
  - Give concrete errors, paths, and constraints up front.
  - End of session: commit in session clone; human runs nut.

DO NOT
  - Start a session without session align (stale clone -> wrong fixes).
  - Push to origin (git push origin main) -- HUMAN ONLY.
  - nut while CLI is running: ${GUARD_TIP}

WHEN HUMAN SAYS "sync" or "nut"
  nut ${PROJECT_NAME}    # see ${GENERIC_GUIDANCE_DIR}/nut.md

================================================================================
Suggested first message to paste into the agent:
================================================================================
New session. init_grok_session.sh complete (session align) -- on main at ${COMMIT}.

Task: <your task in one sentence>
Read: ${GENERIC_GUIDANCE_DIR}/workflow.md, ${PROJECT_GUIDANCE_DIR}/<pick-one-or-two>.md
Constraints: <hardware, files not to touch>
EOF

echo ""
info "Grok session directories: ${GROK_PARENT}/"
info "Canonical local repo:     ${SYNC_REPO}/"
if [[ -n "$ORIGIN_URL" ]]; then
  info "Origin:                   ${ORIGIN_URL}"
fi