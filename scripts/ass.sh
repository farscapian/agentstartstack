#!/usr/bin/env bash
# ass.sh -- human-side git handoff CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ass-aliases.sh
source "${SCRIPT_DIR}/lib/ass-aliases.sh"

_ass_cli_usage() {
  _ass_main_usage
}

_ass_cli_subcommand_help() {
  local sub="${1:-}"
  case "$sub" in
    new)    ass_new --help ;;
    prune)  ass_prune --help ;;
    drop)   ass_drop --help ;;
    up)     ass_up --help ;;
    trim)   ass_up_trim --help ;;
    all)    ass_up_all --help ;;
    status) ass_status --help ;;
    list)   ass_list --help ;;
    sync)   ass_sync --help ;;
    sync-all) ass_sync_all --help ;;
    dropit) dropit --help ;;
    ""|handoff|ass) _ass_main_usage ;;
    *)
      printf '[ERR]  ass: unknown help topic: %s\n' "$sub" >&2
      return 1
      ;;
  esac
}

# True when $1 is a global flag that belongs to ass sync (legacy: bare ass -f).
_ass_cli_is_sync_flag() {
  case "${1:-}" in
    -f|--force|--stashes|-v|-q|--verbose|--quiet|--timestamp|--dry-run) return 0 ;;
    --log-id|--log-id=*) return 0 ;;
    *) return 1 ;;
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
        elif [[ "${2:-}" == sync && "${3:-}" == all ]]; then
          _ass_cli_subcommand_help sync-all
        else
          _ass_cli_subcommand_help "${2}"
        fi
      else
        _ass_cli_usage
      fi
      ;;
    '')
      _ass_cli_usage
      ;;
    new) shift; ass_new "$@" ;;
    prune) shift; ass_prune "$@" ;;
    drop)  shift; ass_drop "$@" ;;
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
    -f|--force|--stashes)
      ass_sync "$@"
      ;;
    --dry-run)
      ass_sync all "$@"
      ;;
    --log-id|--log-id=*)
      ass_sync "$@"
      ;;
    -v|-q|--verbose|--quiet|--timestamp)
      if [[ $# -eq 1 ]]; then
        _ass_cli_usage
      else
        ass_sync "$@"
      fi
      ;;
    --*)
      if _ass_cli_is_sync_flag "$cmd"; then
        ass_sync "$@"
      else
        printf '[ERR]  ass: unknown option: %s (try: ass help)\n' "$cmd" >&2
        return 1
      fi
      ;;
    *)
      printf '[ERR]  ass: unknown command: %s (try: ass help)\n' "$cmd" >&2
      return 1
      ;;
  esac
}

main "$@"