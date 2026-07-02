#!/usr/bin/env bash
# reconcile-cli-guidance.sh -- discovery report for the CLI-guidance CONSUMER-ACTION.
#
# Read-only. Run from a consumer repo root after a bump that introduces
# agentstartstack's generic CLI docs (docs/cli-conventions.md + docs/cli-help.md).
# It lists this project's CLI-related docs and root CLAUDE.md CLI pointers so the
# agent has a concrete worklist to reconcile against the generic guidance:
# trim what is now covered generically, keep only project-specific specifics.
#
# It does NOT edit anything. Reconciliation (deciding generic vs project-specific,
# trimming, refactoring) is a judgement task left to the agent -- this script only
# surfaces the candidates.
#
# Usage:
#   .agentstartstack/scripts/reconcile-cli-guidance.sh
#   scripts/reconcile-cli-guidance.sh            # from the template repo itself

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: reconcile-cli-guidance.sh

Read-only discovery report for the CLI-guidance CONSUMER-ACTION. Run from a
consumer repo root. Lists CLI-related project docs and root CLAUDE.md CLI
pointers to reconcile against the generic .agentstartstack/docs/cli-conventions.md
and cli-help.md. Edits nothing.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) usage >&2; exit 1 ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || { echo "[ERR]  Not inside a git repo." >&2; exit 1; }

# Locate the generic guidance dir. A consumer has the submodule at
# .agentstartstack/ (generic docs under .agentstartstack/docs); the template
# repo itself keeps them under docs/.
GEN_DIR=""
if [[ -e "${REPO_ROOT}/.agentstartstack/.git" && -d "${REPO_ROOT}/.agentstartstack/docs" ]]; then
  GEN_DIR="${REPO_ROOT}/.agentstartstack/docs"
  IS_CONSUMER=1
elif [[ -f "${REPO_ROOT}/docs/cli-conventions.md" ]]; then
  GEN_DIR="${REPO_ROOT}/docs"
  IS_CONSUMER=0
else
  echo "[ERR]  No agentstartstack generic docs found." >&2
  echo "[ERR]    Bump the .agentstartstack submodule first, then re-run." >&2
  exit 1
fi

if [[ ! -f "${GEN_DIR}/cli-conventions.md" ]]; then
  echo "[ERR]  ${GEN_DIR}/cli-conventions.md missing -- bump .agentstartstack first." >&2
  exit 1
fi

echo "[INFO] Generic CLI reference (authoritative):"
echo "[INFO]   ${GEN_DIR#"${REPO_ROOT}/"}/cli-conventions.md  (CLI behavior)"
echo "[INFO]   ${GEN_DIR#"${REPO_ROOT}/"}/cli-help.md         (help-file layout)"
echo ""

if [[ "$IS_CONSUMER" -eq 0 ]]; then
  echo "[OK]   This is the agentstartstack template repo, not a consumer."
  echo "[INFO] Nothing to reconcile here -- this report is for consumer projects."
  exit 0
fi

# Project (host) docs live under docs/ at the consumer root. The generic docs are
# in the submodule, so they are never scanned as project candidates.
PROJ_DIR="${REPO_ROOT}/docs"

# CLI signal: filename mentions cli/command, or the file content carries typical
# CLI-doc markers. False positives are fine -- the agent judges each candidate.
_name_re='(^|[-/])(cli|command|cmd|usage|help)([-.]|$)'
_content_re='subcommand|usage:|--help|\[INFO\]|\[ERROR\]|case "\$(command|cmd)|help menu'

echo "[INFO] Candidate project CLI docs to reconcile (under docs/):"
found=0
if [[ -d "$PROJ_DIR" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    rel="${f#"${REPO_ROOT}/"}"
    signal=""
    if [[ "$(basename "$f")" =~ $_name_re ]]; then
      signal="name"
    elif grep -qiE "$_content_re" "$f" 2>/dev/null; then
      signal="content"
    fi
    if [[ -n "$signal" ]]; then
      printf '[WARN]   %s  (matched: %s)\n' "$rel" "$signal"
      found=$((found + 1))
    fi
  done < <(git -C "$REPO_ROOT" ls-files -- "docs/*.md" 2>/dev/null)
fi
[[ "$found" -eq 0 ]] && echo "[INFO]   (none found under docs/)"
echo ""

# Root CLAUDE.md CLI topic pointers the agent may need to update.
CLAUDE_MD="${REPO_ROOT}/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
  echo "[INFO] Root CLAUDE.md lines mentioning CLI (update pointers as needed):"
  if grep -niE 'cli' "$CLAUDE_MD" 2>/dev/null; then
    :
  else
    echo "[INFO]   (no CLI mentions in CLAUDE.md)"
  fi
  echo ""
fi

cat <<EOF
[INFO] Reconcile (agent judgement -- this script edits nothing):
[INFO]   1. Delete or trim project-local CLI conventions/rules now covered
[INFO]      generically by the two files above; do not keep a forked copy.
[INFO]   2. Refactor what remains under docs/ down to project-specific specifics
[INFO]      only (actual commands, flags, roles/targets, hardware, env vars).
[INFO]   3. Update root CLAUDE.md CLI pointers to reference the generic docs plus
[INFO]      your slimmed project CLI doc.
[INFO]   Commit the reconciliation alongside the submodule bump.
EOF
