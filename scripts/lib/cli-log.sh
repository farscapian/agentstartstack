#!/usr/bin/env bash
# cli-log.sh -- shared CLI logging helpers for agentstartstack consumers.
#
# Sourced by scripts/lib/ass-aliases.sh and by host-project entry scripts.
# See docs/conventions.md (Script output) and docs/cli.md.
#
# shellcheck shell=bash

# Per-invocation output mode (reset by _as_cli_parse_global_flags).
AS_CLI_VERBOSE=0
AS_CLI_QUIET=0
AS_CLI_TIMESTAMP=0
AS_CLI_LOG_ID=""
AS_CLI_LOG_FILE=""

# Host projects override in .agentstartstack.env or before sourcing:
#   AGENTSTARTSTACK_CLI_LOG_DIR   (default: ~/.docs/logs)
#   AGENTSTARTSTACK_CLI_LOG_PREFIX (default: cli) -> <prefix>-<id>.log
: "${AGENTSTARTSTACK_CLI_LOG_DIR:=${HOME}/.agentstartstack/logs}"
: "${AGENTSTARTSTACK_CLI_LOG_PREFIX:=cli}"

_as_cli_resolve_log_file() {
  local id="$1" dir prefix safe
  [[ -n "$id" ]] || return 1
  safe="${id//\//-}"
  safe="${safe#-}"
  [[ -n "$safe" ]] || return 1
  dir="${AGENTSTARTSTACK_CLI_LOG_DIR:-${HOME}/.agentstartstack/logs}"
  prefix="${AGENTSTARTSTACK_CLI_LOG_PREFIX:-cli}"
  printf '%s/%s-%s.log' "$dir" "$prefix" "$safe"
}

_as_cli_timestamp_prefix() {
  [[ "${AS_CLI_TIMESTAMP:-0}" -eq 1 ]] || return 0
  date -Is 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ'
}

_as_cli_log_open() {
  [[ -n "${AS_CLI_LOG_FILE:-}" ]] || return 0
  local dir
  dir=$(dirname "$AS_CLI_LOG_FILE")
  [[ "$dir" == "." || -z "$dir" ]] || mkdir -p "$dir" 2>/dev/null || true
  {
    printf '# log-id %s\n' "${AS_CLI_LOG_ID:-?}"
    printf '# log started %s\n' "$(date -Is 2>/dev/null || date)"
    printf '# pwd %s\n' "$(pwd 2>/dev/null || echo '?')"
  } >> "$AS_CLI_LOG_FILE"
}

_as_cli_log_append() {
  [[ -n "${AS_CLI_LOG_FILE:-}" ]] || return 0
  local dir
  dir=$(dirname "$AS_CLI_LOG_FILE")
  [[ "$dir" == "." || -z "$dir" ]] || mkdir -p "$dir" 2>/dev/null || true
  # shellcheck disable=SC2129
  printf '%s' "$1" >> "$AS_CLI_LOG_FILE"
}

_as_cli_emit() {
  local level="$1" stream="$2" tag="$3"
  shift 3
  local ts prefix line
  ts=$(_as_cli_timestamp_prefix)
  if [[ -n "$ts" ]]; then
    prefix="${ts} "
  else
    prefix=""
  fi
  line="${prefix}${tag}$*"$'\n'
  [[ -n "${AS_CLI_LOG_FILE:-}" ]] && _as_cli_log_append "$line"

  [[ "${AS_CLI_QUIET:-0}" -eq 0 || "$level" == ERR ]] || return 0
  if [[ "$stream" == stderr ]]; then
    printf '%s%s ' "$prefix" "$tag" >&2
    printf '%s\n' "$*" >&2
  else
    printf '%s%s ' "$prefix" "$tag"
    printf '%s\n' "$*"
  fi
}

_as_cli_emitf() {
  local level="$1" stream="$2" tag="$3" fmt="$4"
  shift 4
  local ts prefix body
  ts=$(_as_cli_timestamp_prefix)
  if [[ -n "$ts" ]]; then
    prefix="${ts} "
  else
    prefix=""
  fi
  # shellcheck disable=SC2059
  body=$(printf "$fmt" "$@")
  [[ -n "${AS_CLI_LOG_FILE:-}" ]] && _as_cli_log_append "${prefix}${tag}${body}"

  [[ "${AS_CLI_QUIET:-0}" -eq 0 || "$level" == ERR ]] || return 0
  if [[ "$stream" == stderr ]]; then
    printf '%s%s ' "$prefix" "$tag" >&2
    # shellcheck disable=SC2059
    printf "$fmt" "$@" >&2
  else
    printf '%s%s ' "$prefix" "$tag"
    # shellcheck disable=SC2059
    printf "$fmt" "$@"
  fi
}

_as_cli_info()  { _as_cli_emit INFO stdout '[INFO]' "$@"; }
_as_cli_ok()    { _as_cli_emit OK   stdout '[OK]   ' "$@"; }
_as_cli_warn()  { _as_cli_emit WARN stderr '[WARN]' "$@"; }
_as_cli_err()   { _as_cli_emit ERR  stderr '[ERR]  ' "$@"; }
_as_cli_debug() {
  [[ "${AS_CLI_VERBOSE:-0}" -eq 1 ]] || return 0
  _as_cli_emit DEBUG stderr '[DEBUG]' "$@"
}

_as_cli_infof()  { _as_cli_emitf INFO  stdout '[INFO]' "$@"; }
_as_cli_okf()    { _as_cli_emitf OK    stdout '[OK]   ' "$@"; }
_as_cli_warnf()  { _as_cli_emitf WARN  stderr '[WARN]' "$@"; }
_as_cli_errf()   { _as_cli_emitf ERR   stderr '[ERR]  ' "$@"; }
_as_cli_debugf() {
  [[ "${AS_CLI_VERBOSE:-0}" -eq 1 ]] || return 0
  _as_cli_emitf DEBUG stderr '[DEBUG]' "$@"
}

# Strip global output flags from "$@" and store the remainder in the nameref $1.
# Returns 1 on invalid flag combinations.
_as_cli_parse_global_flags() {
  local -n _as_cli_out=$1
  shift
  _as_cli_out=()
  AS_CLI_VERBOSE=0
  AS_CLI_QUIET=0
  AS_CLI_TIMESTAMP=0
  AS_CLI_LOG_ID=""
  AS_CLI_LOG_FILE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v|--verbose)
        AS_CLI_VERBOSE=1
        ;;
      -q|--quiet)
        AS_CLI_QUIET=1
        ;;
      --timestamp)
        AS_CLI_TIMESTAMP=1
        ;;
      --log-id=*)
        AS_CLI_LOG_ID="${1#--log-id=}"
        ;;
      --log-id)
        shift
        AS_CLI_LOG_ID="${1:-}"
        if [[ -z "$AS_CLI_LOG_ID" ]]; then
          printf '[ERR]  cli-log: --log-id requires an id\n' >&2
          return 1
        fi
        shift
        _as_cli_out+=("$@")
        _as_cli_parse_global_flags_finalize || return 1
        return 0
        ;;
      --)
        shift
        _as_cli_out+=("$@")
        _as_cli_parse_global_flags_finalize || return 1
        return 0
        ;;
      -*)
        _as_cli_out+=("$1")
        ;;
      *)
        _as_cli_out+=("$@")
        _as_cli_parse_global_flags_finalize || return 1
        return 0
        ;;
    esac
    shift
  done

  _as_cli_parse_global_flags_finalize
}

_as_cli_parse_global_flags_finalize() {
  if [[ -z "${AS_CLI_LOG_ID:-}" ]]; then
    AS_CLI_LOG_FILE=""
    return 0
  fi
  if [[ "${AS_CLI_QUIET:-0}" -eq 1 ]]; then
    printf '[ERR]  cli-log: --log-id is incompatible with -q/--quiet\n' >&2
    return 1
  fi
  AS_CLI_LOG_FILE=$(_as_cli_resolve_log_file "$AS_CLI_LOG_ID") || {
    printf '[ERR]  cli-log: invalid --log-id\n' >&2
    return 1
  }
  AS_CLI_VERBOSE=1
  AS_CLI_TIMESTAMP=1
  _as_cli_log_open
  return 0
}

# Rebuild global argv flags for nested command calls (e.g. nutupyall -> nutup).
_as_cli_global_argv() {
  local -n _as_cli_glob=$1
  _as_cli_glob=()
  [[ "${AS_CLI_VERBOSE:-0}" -eq 1 ]] && _as_cli_glob+=(-v)
  [[ "${AS_CLI_QUIET:-0}" -eq 1 ]] && _as_cli_glob+=(-q)
  [[ "${AS_CLI_TIMESTAMP:-0}" -eq 1 ]] && _as_cli_glob+=(--timestamp)
  [[ -n "${AS_CLI_LOG_ID:-}" ]] && _as_cli_glob+=(--log-id="${AS_CLI_LOG_ID}")
}