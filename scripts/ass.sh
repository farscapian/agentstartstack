#!/usr/bin/env bash
# ass.sh -- human-side git handoff CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ass-aliases.sh
source "${SCRIPT_DIR}/lib/ass-aliases.sh"

_ass_cli_usage() {
  cat <<'EOF'
ass.sh -- AgentStartStack handoff (human-side git handoff)

Pwd-oriented: cd to the canonical repo or a session clone, then run a command.
After install-shell-aliases.sh, only a thin ass() wrapper is installed.

  ass.sh [-f] [--skip]            local-sync handoff (ass)
  ass.sh new --grok|--claude      create + align a session clone (canonical pwd)
  ass.sh prune [<clone-path>]     consolidate one clone into the newest, then remove it
  ass.sh up [-f]                  local-sync, then git push origin main
  ass.sh up trim [options]        consolidate and prune stale session clones
  ass.sh up --all                 ass up agentstartstack, refresh consumer submodules
  ass.sh status                   ahead/behind origin/main for canonical + session clones
  ass.sh list                     session clones for canonical pwd (by origin URL)
  ass.sh sync [--dry-run]         align behind session clones to canonical (canonical pwd)
  ass.sh dropit <src> [dest]      copy generic work into agentstartstack session clone

Global flags: -v, -q, --timestamp, --log-id=ID, --create-log (see docs/cli.md)
EOF
}

_ass_cli_subcommand_help() {
  local sub="${1:-}"
  case "$sub" in
    new)    ass_new --help ;;
    prune)  ass_prune --help ;;
    up)     ass_up --help ;;
    trim)   ass_up_trim --help ;;
    all)    ass_up_all --help ;;
    status) ass_status --help ;;
    list)   ass_list --help ;;
    sync)   ass_sync --help ;;
    dropit) dropit --help ;;
    ""|handoff|ass) ass --help ;;
    *)
      printf '[ERR]  ass.sh: unknown help topic: %s\n' "$sub" >&2
      return 1
      ;;
  esac
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    -h|--help|help)
      if [[ -n "${2:-}" ]]; then
        if [[ "${2:-}" == up && "${3:-}" == trim ]]; then
          _ass_cli_subcommand_help trim
        elif [[ "${2:-}" == up && "${3:-}" == --all ]]; then
          _ass_cli_subcommand_help all
        else
          _ass_cli_subcommand_help "${2}"
        fi
      else
        _ass_cli_usage
      fi
      ;;
    new) shift; ass_new "$@" ;;
    prune) shift; ass_prune "$@" ;;
    up)
      shift
      if [[ "${1:-}" == trim ]]; then
        shift; ass_up_trim "$@"
      elif [[ "${1:-}" == --all ]]; then
        shift; ass_up_all "$@"
      else
        ass_up "$@"
      fi
      ;;
    dropit) shift; dropit "$@" ;;
    status) shift; ass_status "$@" ;;
    list)   shift; ass_list "$@" ;;
    sync)   shift; ass_sync "$@" ;;
    *) ass "$@" ;;
  esac
}

main "$@"