#!/usr/bin/env bash
# setup.sh -- ensure the `ass` command is available in your shell.
#
# Run from the root of this repo:
#
#   ./setup.sh
#
# Thin entry point: delegates to scripts/install-shell-aliases.sh (the single
# source of truth), which idempotently writes a managed `ass()` wrapper into
# ~/.bash_aliases and ensures ~/.bashrc sources it. No sudo, no system files --
# everything lives under $HOME and inside this repo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
err()  { printf '[ERR]  %s\n' "$*" >&2; exit 1; }

INSTALLER="${REPO_ROOT}/scripts/install-shell-aliases.sh"
[[ -f "$INSTALLER" ]] || err "Installer not found: $INSTALLER (run setup.sh from the repo root)"

info "Ensuring the 'ass' command is available..."
bash "$INSTALLER"

ok "'ass' is wired up. Load it into your current shell with:"
info "  source ~/.bashrc"
info "Then verify with: ass help"
