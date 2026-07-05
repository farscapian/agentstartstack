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
Usage: init_grok_session.sh [--non-interactive] [session-clone-path]

Session align for the authorized AI git workflow: aligns a Grok/Cursor session
clone with the canonical local repo and prints reminders for efficient agent use.

  --non-interactive, -y   Never prompt (for hooks/automation). Refuses to run on
                          canonical and refuses to discard a dirty clone, rather
                          than asking. A fresh, clean worktree aligns silently.
EOF
}

# Separate flags from the optional positional session-clone path.
NONINTERACTIVE=0
PATH_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --non-interactive|-y|--yes) NONINTERACTIVE=1; shift ;;
    --) shift; [[ $# -gt 0 ]] && PATH_ARG="$1"; break ;;
    -*) err "Unknown option: $1 (see --help)" ;;
    *) [[ -z "$PATH_ARG" ]] || err "Unexpected extra argument: $1"; PATH_ARG="$1"; shift ;;
  esac
done

# A hook has no controlling tty; if /dev/tty cannot actually be opened, force
# non-interactive so a prompt never hangs or crashes under set -e. (-r alone is
# unreliable: /dev/tty is readable by permission even with no controlling tty.)
{ true </dev/tty; } 2>/dev/null || NONINTERACTIVE=1

resolve_repo_root() {
  local arg="${1:-}"
  if [[ -n "$arg" ]]; then
    [[ -d "$arg" ]] || err "Session path not found: $arg"
    (cd "$arg" && pwd)
    return 0
  fi
  git rev-parse --show-toplevel 2>/dev/null || true
}

REPO_ROOT="$(resolve_repo_root "$PATH_ARG")"
[[ -n "$REPO_ROOT" ]] || err "Not inside a git repo. Pass the session clone path as an argument."

agentstartstack_load_config "$REPO_ROOT" \
  || err "Missing .agentstartstack.env (run add-to-project.sh, or 'ass adopt' this worktree)"
agentstartstack_apply_defaults || exit 1
agentstartstack_resolve_guidance_paths "$REPO_ROOT" || err "Cannot resolve guidance paths"

if [[ "$(readlink -f "$REPO_ROOT")" == "$(readlink -f "$CANONICAL_LOCAL_REPO")" ]]; then
  warn "Current directory is the canonical local repo, not a Grok session clone."
  warn "Init is intended for a session clone under one of: ${AGENT_SESSION_CLONE_PARENT}"
  if [[ "$NONINTERACTIVE" == 1 ]]; then
    err "Refusing to run on canonical in non-interactive mode (never edit canonical)."
  fi
  read -r -p "Continue anyway? [y/N] " confirm </dev/tty
  [[ "${confirm,,}" == "y" || "${confirm,,}" == "yes" ]] || exit 0
fi

cd "$REPO_ROOT"
git rev-parse --is-inside-work-tree &>/dev/null || err "Not a git work tree: $REPO_ROOT"

info "Session clone: $REPO_ROOT"
info "Canonical:     $CANONICAL_LOCAL_REPO"
info "Project:       ${DISPLAY_NAME} (${PROJECT_NAME})"
echo ""

# Re-running init re-aligns via a hard reset + clean, which discards uncommitted
# work. If the session clone is dirty, confirm before destroying it. Exclude
# .agentstartstack.env: ass adopt writes worktree-specific config into it, so a fresh
# worktree is "dirty" by that file alone -- it is init-generated, not agent work,
# and the reset below re-aligns it anyway. Any OTHER dirt is real work.
WORKTREE_DIRTY=0
if [[ -n "$(git status --porcelain 2>/dev/null -- . ':(exclude).agentstartstack.env')" ]]; then
  WORKTREE_DIRTY=1
  warn "Session clone has uncommitted changes; re-aligning will HARD RESET and discard them:"
  git status --short >&2
  if [[ "$NONINTERACTIVE" == 1 ]]; then
    err "Refusing to discard a dirty clone in non-interactive mode; commit or align it by hand."
  fi
  read -r -p "Discard and re-align? [y/N] " confirm </dev/tty
  if [[ "${confirm,,}" != "y" && "${confirm,,}" != "yes" ]]; then
    info "Aborted; clone left as-is."
    exit 0
  fi
fi

info "Session align: fetching local-sync/main and aligning..."
if git remote get-url local-sync &>/dev/null; then
  git remote set-url local-sync "$CANONICAL_LOCAL_REPO"
else
  git remote add local-sync "$CANONICAL_LOCAL_REPO"
fi

git fetch local-sync main

# Unlanded-commit guard. The dirty-tree check above only covers UNCOMMITTED work; it
# does not protect commits the agent made in the clone that are ahead of
# local-sync/main but not yet landed on canonical. A hard reset to local-sync/main
# would silently drop those from HEAD (recoverable only via reflog). Detect them and
# -- matching the SessionStart bootstrap's fast-forward-only guarantee -- refuse
# (non-interactive) or require explicit confirmation (interactive). Land them first:
# commit in the clone -> ass sync -> only then re-align.
AHEAD_COUNT=$(git rev-list --count local-sync/main..HEAD 2>/dev/null || echo 0)
if [[ "$AHEAD_COUNT" -gt 0 ]]; then
  warn "Session clone has ${AHEAD_COUNT} commit(s) ahead of local-sync/main not yet landed on canonical;"
  warn "re-aligning will HARD RESET and drop them from HEAD (recoverable only via reflog):"
  git log --oneline local-sync/main..HEAD >&2
  if [[ "$NONINTERACTIVE" == 1 ]]; then
    err "Refusing to discard unlanded commits in non-interactive mode; land them (ass sync) or align by hand."
  fi
  read -r -p "Discard ${AHEAD_COUNT} unlanded commit(s) and re-align? [y/N] " confirm </dev/tty
  if [[ "${confirm,,}" != "y" && "${confirm,,}" != "yes" ]]; then
    info "Aborted; clone left as-is."
    exit 0
  fi
fi

# Prefer a real fast-forward when the clone is clean and does not diverge -- the
# common case then never needs a destructive reset. Fall back to a hard reset only
# to discard work already confirmed above: unlanded commits (AHEAD_COUNT) or a dirty
# tree (WORKTREE_DIRTY).
if [[ "$AHEAD_COUNT" -eq 0 && "$WORKTREE_DIRTY" -eq 0 ]]; then
  git merge --ff-only local-sync/main
else
  git reset --hard local-sync/main
  git clean -fd
fi
if [[ -f .gitmodules ]]; then
  git submodule update --init --recursive
fi

# Stamp session align time so ass -f can prefer this session over older ones.
# Resolve the real git dir so markers work for a linked worktree (.git is a gitfile
# -> <canonical>/.git/worktrees/<name>), not just a full clone (.git is a directory).
GITDIR=$(git -C "$REPO_ROOT" rev-parse --absolute-git-dir 2>/dev/null || echo "${REPO_ROOT}/.git")
date +%s > "${GITDIR}/agentstartstack-session-init"
printf '%s\n' grok > "${GITDIR}/agentstartstack-session-agent"

# Harden origin to fetch-only so agents never push to origin -- but ONLY for an
# independent full clone. A linked git worktree shares canonical's config/remotes,
# so disabling the push URL here would also disable it on canonical. Skip it there.
case "$GITDIR" in
  */.git/worktrees/*) : ;;
  *)
    if git remote get-url origin &>/dev/null; then
      git remote set-url --push origin DISABLED
    fi
    ;;
esac

# Surface a pending agentstartstack bump dropped by ass publish (see workflow.md).
# Backstop: if there is no watch file but the .agentstartstack submodule is behind
# its remote (e.g. ass publish deferred an action-bearing bump), surface it anyway.
if [[ -f "${REPO_ROOT}/.agentstartstack-bump" ]]; then
  warn "Pending agentstartstack bump: $(head -1 "${REPO_ROOT}/.agentstartstack-bump")"
  warn "  Commits are BLOCKED until you reconcile this consumer and remove the file"
  warn "  (see docs/workflow.md: 'The .agentstartstack-bump watch file')."
elif RECONCILE_RANGE=$(agentstartstack_pending_reconcile "$REPO_ROOT"); then
  if agentstartstack_range_has_consumer_action "$REPO_ROOT" "$RECONCILE_RANGE"; then
    # Action-bearing bump deferred by ass publish with no in-flight clone to flag.
    # Drop the watch file now so the pre-commit reminder keeps resurfacing until
    # this agent reconciles -- same persistent flag as the in-flight path. It does
    # not block commits; the bump is handled eventually, not treated as a blocker.
    agentstartstack_drop_bump_flag "$REPO_ROOT" \
      "agentstartstack bump pending (deferred by ass publish): ${RECONCILE_RANGE}" \
      "This delta carries CONSUMER-ACTION(s) -- perform each one during reconcile." || true
    warn "Deferred agentstartstack bump carries CONSUMER-ACTION(s): ${RECONCILE_RANGE}"
    warn "  Dropped .agentstartstack-bump -- commits are BLOCKED until you reconcile."
    warn "  Read the producer commits oldest-first, run each CONSUMER-ACTION, then bump:"
    warn "    git -C .agentstartstack log --reverse --format='%H%n%B' ${RECONCILE_RANGE}"
    warn "  (see docs/workflow.md: 'The .agentstartstack-bump watch file')."
  else
    warn "agentstartstack is behind its remote -- reconcile pending (no watch file): ${RECONCILE_RANGE}"
    warn "  Read the producer commits oldest-first, then bump:"
    warn "    git -C .agentstartstack log --reverse --format='%H%n%B' ${RECONCILE_RANGE}"
    warn "  (see docs/workflow.md: 'The .agentstartstack-bump watch file')."
  fi
elif ACTION_RANGE=$(agentstartstack_pending_consumer_actions "$REPO_ROOT"); then
  # Pointer is current but CONSUMER-ACTION(s) after the watermark were never done.
  # Hard-block until the actions are performed and the watermark recorded.
  agentstartstack_drop_bump_flag "$REPO_ROOT" \
    "Unapplied agentstartstack CONSUMER-ACTION(s): ${ACTION_RANGE}" \
    "Pointer is current; the watermark lags. Run the actions, then .docs/scripts/record-consumer-action-seen.sh <OLD> <NEW> before removing this file." || true
  warn "Unapplied CONSUMER-ACTION(s) -- submodule pointer is current but watermark lags: ${ACTION_RANGE}"
  warn "  Dropped .agentstartstack-bump -- commits are BLOCKED until you reconcile."
  warn "  Read the producer commits oldest-first, run each CONSUMER-ACTION, then update:"
  warn "    git -C .agentstartstack log --reverse --format='%H%n%B' ${ACTION_RANGE}"
  warn "    .docs/scripts/record-consumer-action-seen.sh <OLD> <NEW>"
  warn "  (see docs/workflow.md: 'CONSUMER-ACTION watermark')."
fi

# Install the pre-commit reminder (warns but never blocks while
# .agentstartstack-bump is pending; chains to shellcheck). Shared with
# install-githooks.sh so the two converge -- running either installs the same hook.
"${SCRIPT_DIR}/install-precommit-guard.sh" "$REPO_ROOT"
info "Pre-commit reminder active (warns but does not block while .agentstartstack-bump pending; chains to shellcheck)."

# Auto-commit any session work left in the tree (see docs/workflow.md HARD RULES).
"${SCRIPT_DIR}/auto-commit-session-work.sh" "$REPO_ROOT" || true

# Refresh the human-side ass() wrapper (idempotent managed block in ~/.bash_aliases).
if "${SCRIPT_DIR}/install-shell-aliases.sh"; then
  info "Shell alias (ass) refreshed; run 'source ~/.bashrc' if it changed."
else
  warn "Shell alias install skipped (non-fatal)."
fi

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
  2. Handoff       -- human runs ass (never git push origin from agents)

GUIDANCE LOCATIONS
  Generic:  ${GENERIC_GUIDANCE_DIR}/  (workflow, ass, conventions, security)
  Project:  ${PROJECT_GUIDANCE_DIR}/   (CLI, architecture, gotchas)

FIRST MESSAGE (copy/paste template below)
  - Say you ran init_grok_session.sh (session align complete).
  - State your task in one sentence.
  - Name 1-3 guidance files to read (not all of them, not CLAUDE.md in full).

WHAT TO READ (pick 1-3)
  Git / session / handoff     -> ${GENERIC_GUIDANCE_DIR}/workflow.md, ass.md
  New shell script            -> ${GENERIC_GUIDANCE_DIR}/conventions.md, code-quality.md
  Secrets / env               -> ${GENERIC_GUIDANCE_DIR}/security.md
  Terminal copy/paste         -> ${GENERIC_GUIDANCE_DIR}/terminal.md
  Project-specific tasks      -> ${PROJECT_GUIDANCE_DIR}/<topic>.md per CLAUDE.md index

  CLAUDE.md is an index only. Do not ask the agent to read all guidance files.

TOKEN TIPS
  - Session align once per session (this script), not before every task.
  - Give concrete errors, paths, and constraints up front.
  - End of session: commit in session clone; human runs ass.

DO NOT
  - Start a session without session align (stale clone -> wrong fixes).
  - Push to origin (git push origin main) -- HUMAN ONLY.
  - ass while CLI is running: ${GUARD_TIP}

WHEN HUMAN SAYS "sync" or "ass"
  cd ${CANONICAL_LOCAL_REPO} && ass    # see ${GENERIC_GUIDANCE_DIR}/ass.md

================================================================================
Suggested first message to paste into the agent:
================================================================================
New session. init_grok_session.sh complete (session align) -- on main at ${COMMIT}.

Task: <your task in one sentence>
Read: ${GENERIC_GUIDANCE_DIR}/workflow.md, ${PROJECT_GUIDANCE_DIR}/<pick-one-or-two>.md
Constraints: <hardware, files not to touch>
EOF

echo ""
info "Grok session clones:      under ${AGENT_SESSION_CLONE_PARENT}"
info "Canonical local repo:     ${CANONICAL_LOCAL_REPO}/"
if [[ -n "$ORIGIN_URL" ]]; then
  info "Origin:                   ${ORIGIN_URL}"
fi