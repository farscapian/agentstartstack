#!/usr/bin/env bash
# ass.sh -- human-side git handoff CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ass-aliases.sh
source "${SCRIPT_DIR}/lib/ass-aliases.sh"

_ass_cli_usage() {
  _ass_main_usage
}

# Read LOG_TO_FILE from the pwd repo's .agentstartstack.env without sourcing it
# (avoids pulling in other env vars). Echoes the raw value, comments stripped.
_ass_cli_env_value() {
  local key="$1" root env line
  root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
  env="${root}/.agentstartstack.env"
  [[ -f "$env" ]] || return 1
  line=$(grep -E "^[[:space:]]*${key}=" "$env" 2>/dev/null | tail -1) || return 1
  line="${line#*=}"
  line="${line%%#*}"
  printf '%s' "$line" | tr -d '[:space:]'
}

# When LOG_TO_FILE=1 (in the repo's .agentstartstack.env), append a full transcript
# of this invocation to ~/.agentstartstack/ass.log (override: AGENTSTARTSTACK_LOG_FILE).
# Output is tee'd, so colors auto-disable and the log stays clean ASCII.
_ass_cli_start_file_log() {
  local val log dir
  val=$(_ass_cli_env_value LOG_TO_FILE) || return 0
  case "$val" in 1|true|yes|on) ;; *) return 0 ;; esac
  log="${AGENTSTARTSTACK_LOG_FILE:-${HOME}/.agentstartstack/ass.log}"
  dir=$(dirname "$log")
  mkdir -p "$dir" 2>/dev/null || true
  printf '\n===== ass %s | pwd %s | args: %s =====\n' \
    "$(date -Is 2>/dev/null || date)" "$(pwd 2>/dev/null || echo '?')" "$*" \
    >> "$log" 2>/dev/null || return 0
  exec > >(tee -a "$log") 2>&1
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
    adopt) shift; ass_adopt "$@" ;;
    discover) shift; ass_discover "$@" ;;
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

_ass_cli_start_file_log "$@"
main "$@"