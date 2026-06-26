#!/usr/bin/env bash
# ass.sh -- human-side git handoff CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ass-aliases.sh
source "${SCRIPT_DIR}/lib/ass-aliases.sh"

_ass_cli_usage() {
  _ass_main_usage
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
        ass_help_topic "${2}" "${3:-}"
      else
        _ass_cli_usage
      fi
      ;;
    '')
      _ass_cli_usage
      ;;
    new) shift; ass_new "$@" ;;
    drop)  shift; ass_drop "$@" ;;
    publish) shift; ass_publish "$@" ;;
    up)
      shift
      if [[ "${1:-}" == trim ]]; then
        shift; ass_up_trim "$@"
      elif [[ "${1:-}" == --all || "${1:-}" == all ]]; then
        printf '[ERR]  ass up --all has been renamed: use "ass publish" (try: ass publish help)\n' >&2
        return 1
      else
        ass_up "$@"
      fi
      ;;
    status) shift; ass_status "$@" ;;
    info)   shift; ass_info "$@" ;;
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