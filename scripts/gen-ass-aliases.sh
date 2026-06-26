#!/usr/bin/env bash
# gen-ass-aliases.sh -- generate scripts/lib/ass-aliases.sh from nut-aliases.sh
# Prefer: python3 scripts/restore-ass-migration.py (full migration + git commits)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

if command -v python3 >/dev/null 2>&1; then
  exec python3 scripts/restore-ass-migration.py --aliases-only
fi

echo "[ERR]  python3 required to generate ass-aliases.sh" >&2
exit 1