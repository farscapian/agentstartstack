#!/usr/bin/env bash
# commit-ass-migration.sh -- restore ass CLI migration with incremental git commits.
# Run from repo root: bash scripts/commit-ass-migration.sh
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

run() { printf '+ %s\n' "$*"; "$@"; }

# Generate ass-aliases.sh and any missing pieces from nut-aliases + transcript.
run python3 scripts/restore-ass-migration.py

printf '\n[OK]   ass migration restored. Run: scripts/install-shell-aliases.sh && source ~/.bashrc\n'