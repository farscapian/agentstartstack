#!/usr/bin/env bash
# ass-aliases.sh -- ass CLI implementation library (sourced by scripts/ass.sh).
#
# Command entry point: scripts/ass.sh. install-shell-aliases.sh installs a thin
# ass() wrapper only. docs/ass.md documents usage.
#
# shellcheck shell=bash

# Retired names -- clear if still loaded in this shell.
unset -f land s2s s2ps s2is push nut nutup nutupyall nutup_trim dropit assup assupyall assitup 2>/dev/null

#
# Single source of truth for the human-side git-handoff aliases. Installed into
# the human's shell by install-shell-aliases.sh (which both init_*_session.sh
# call); do not execute directly -- it is meant to be sourced. ass.md documents
# usage and points here; edit this file, then re-run install-shell-aliases.sh.
#
# shellcheck shell=bash

# Retired names -- clear if still loaded in this shell.
unset -f land s2s s2ps s2is push 2>/dev/null

# Shared CLI logging (docs/cli.md, conventions.md -- Script output).
_ASS_ALIASES_LIB_DIR=$(
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
)
# shellcheck source=session-clones.sh
source "${_ASS_ALIASES_LIB_DIR}/session-clones.sh"
# AGENT_SESSION_CLONE_PARENT and ASS_NEW_SESSION_CLONE_ROOT come from session-clones.sh.
# Override AGENT_SESSION_CLONE_PARENT before sourcing ass-aliases to customize discovery.
# shellcheck source=cli-log.sh
source "${_ASS_ALIASES_LIB_DIR}/cli-log.sh"
: "${AGENTSTARTSTACK_CLI_LOG_PREFIX:=ass}"
: "${AGENTSTARTSTACK_CLI_LOG_DIR:=${HOME}/.docs/logs}"

_ASS_REPO_ROOT="$(cd "${_ASS_ALIASES_LIB_DIR}/../.." && pwd)"
_ASS_HELP_DIR="${_ASS_REPO_ROOT}/docs/help"

# Print a help menu from docs/help/ (iotstack-style external .txt files).
_ass_cat_help() {
  local file="${_ASS_HELP_DIR}/$1"
  if [[ ! -f "$file" ]]; then
    _ass_err "ass: help file missing: ${file}"
    return 1
  fi
  cat "$file"
  # Ensure help menus end with a newline (prompt-friendly in the terminal).
  if [[ -s "$file" ]] && [[ -n $(tail -c 1 "$file" | tr -d '\n') ]]; then
    printf '\n'
  fi
}

_ass_help_requested() {
  case "${1:-}" in
    help|-h|--help) return 0 ;;
    *) return 1 ;;
  esac
}

_ass_main_usage() { _ass_cat_help ass.txt; }
ass_help_sync() { _ass_cat_help ass-sync.txt; }
ass_help_sync_all() { _ass_cat_help ass-sync-all.txt; }
ass_help_new() { _ass_cat_help ass-new.txt; }
ass_help_list() { _ass_cat_help ass-list.txt; }
ass_help_status() { _ass_cat_help ass-status.txt; }
ass_help_info() { _ass_cat_help ass-info.txt; }
ass_help_drop() { _ass_cat_help ass-drop.txt; }
ass_help_up() { _ass_cat_help ass-up.txt; }
ass_help_up_trim() { _ass_cat_help ass-up-trim.txt; }
ass_help_up_all() { _ass_cat_help ass-up-all.txt; }

# ass help <topic> and ass help <parent> <nested> (ass.sh entry).
ass_help_topic() {
  local topic="${1:-}" nested="${2:-}"
  case "$topic" in
    ""|ass|handoff) _ass_main_usage ;;
    sync)
      if [[ "$nested" == all ]]; then
        ass_help_sync_all
      else
        ass_help_sync
      fi
      ;;
    up)
      case "$nested" in
        trim) ass_help_up_trim ;;
        --all|all) ass_help_up_all ;;
        *) ass_help_up ;;
      esac
      ;;
    new) ass_help_new ;;
    list) ass_help_list ;;
    status) ass_help_status ;;
    info) ass_help_info ;;
    drop) ass_help_drop ;;
    trim) ass_help_up_trim ;;
    *)
      _ass_err "ass: unknown help topic: ${topic}"
      return 1
      ;;
  esac
}

_ass_info()   { _as_cli_info "$@"; }
_ass_ok()     { _as_cli_ok "$@"; }
_ass_warn()   { _as_cli_warn "$@"; }
_ass_err()    { _as_cli_err "$@"; }
_ass_debug()  { _as_cli_debug "$@"; }
_ass_infof()  { _as_cli_infof "$@"; }
_ass_okf()    { _as_cli_okf "$@"; }
_ass_warnf()  { _as_cli_warnf "$@"; }
_ass_errf()   { _as_cli_errf "$@"; }
_ass_debugf() { _as_cli_debugf "$@"; }


# True if $1 lies under any AGENT_SESSION_CLONE_PARENT entry (session clones must
# not be used as AGENTSTARTSTACK_PROJECT_ROOTS -- canonical repos live elsewhere).
_agentstartstack_under_session_clone_parent() {
  local path="$1" parents base
  [[ -n "$path" ]] || return 1
  path="$(readlink -f "$path" 2>/dev/null || echo "$path")"
  parents="${AGENT_SESSION_CLONE_PARENT}"
  local IFS=:
  for base in $parents; do
    [[ -n "$base" ]] || continue
    base="$(readlink -f "$base" 2>/dev/null || echo "$base")"
    [[ "$path" == "$base" || "$path" == "$base"/* ]] && return 0
  done
  return 1
}

# True if colon-separated $1 is a valid AGENTSTARTSTACK_PROJECT_ROOTS value.
_agentstartstack_project_roots_valid() {
  local roots="$1" r
  [[ -n "$roots" ]] || return 1
  local IFS=:
  for r in $roots; do
    [[ -n "$r" ]] || continue
    _agentstartstack_under_session_clone_parent "$r" && return 1
  done
  return 0
}

_agentstartstack_guard_project_roots() {
  local roots="${AGENTSTARTSTACK_PROJECT_ROOTS:-}"
  [[ -n "$roots" ]] || return 0
  _agentstartstack_project_roots_valid "$roots" && return 0
  printf 'ass: AGENTSTARTSTACK_PROJECT_ROOTS must not point under AGENT_SESSION_CLONE_PARENT (%s)\n' \
    "$roots" >&2
  printf 'ass:   export AGENTSTARTSTACK_PROJECT_ROOTS to the dir holding canonical checkouts (e.g. ~/Sync/mini_projects)\n' >&2
  printf 'ass:   then re-run scripts/install-shell-aliases.sh and source ~/.bashrc\n' >&2
  return 1
}

_agentstartstack_guard_project_roots || true

# ass / ass up -- Newest commit Until Transferred
#
# Usage:
#   nut              # local-sync with canonical local repo
#   nut -f           # local-sync from a session clone initialized after last ass
#   nutup            # local-sync, then git push origin main
#   nutup -f         # as nut -f, then push
#   nutup iotstack   # explicit repo + local-sync + push
#   ass_up_all        # nutup agentstartstack, refresh consumer submodules
#
# Timestamp markers (machine-local, under .git/):
#   canonical:  .git/agentstartstack-ass-last      (unix time; set after each nut)
#   session:    .git/agentstartstack-session-init  (unix time; set by init_*_session.sh)

# Locate a canonical repo named "$1" under any of AGENTSTARTSTACK_PROJECT_ROOTS
# (colon-separated dirs that hold repo checkouts as <root>/<name>). No location
# is assumed -- if the var is empty, name-based lookup fails (pwd-based nut still
# works). install-shell-aliases.sh seeds a default from the install location.
_ass_sync_root() {
  local repo_name="$1"
  local roots="${AGENTSTARTSTACK_PROJECT_ROOTS:-}"
  local root
  local IFS=:

  [[ -n "$roots" ]] || return 1
  _agentstartstack_project_roots_valid "$roots" || return 1
  for root in $roots; do
    [[ -n "$root" ]] || continue
    if [[ -d "${root}/${repo_name}/.git" ]]; then
      printf '%s/%s\n' "$root" "$repo_name"
      return 0
    fi
  done

  return 1
}

# Consumer repo name -> session clones (via agent_session_clones_list).
_ass_session_clones_for_consumer() {
  local name="$1" canonical origin
  canonical=$(_ass_sync_root "$name") || return 0
  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || return 0
  agent_session_clones_list "$origin"
}

# Resolve canonical local repo from a session clone path.
_ass_sync_target_from_worktree() {
  local wt="$1" origin roots root candidate got

  if git -C "$wt" remote get-url local-sync &>/dev/null 2>&1; then
    readlink -f "$(git -C "$wt" remote get-url local-sync)"
    return 0
  fi

  # Fallback (no local-sync remote): match this clone's origin URL against the
  # canonical repos under AGENTSTARTSTACK_PROJECT_ROOTS -- no path-name assumption.
  origin=$(git -C "$wt" remote get-url origin 2>/dev/null) || return 1
  roots="${AGENTSTARTSTACK_PROJECT_ROOTS:-}"
  [[ -n "$roots" ]] || return 1
  local IFS=:
  for root in $roots; do
    [[ -n "$root" ]] || continue
    for candidate in "$root"/*/; do
      [[ -d "${candidate}.git" ]] || continue
      got=$(git -C "$candidate" remote get-url origin 2>/dev/null) || continue
      [[ "$got" == "$origin" ]] && { readlink -f "${candidate%/}"; return 0; }
    done
  done

  return 1
}

# Block while long-running repo tools are active on the canonical local repo.
_ass_guard_active_sessions() {
  local sync_target="$1"

  # Match on the repo directory name (basename of the resolved canonical path),
  # so the guard is independent of where the human keeps their checkouts.
  case "${sync_target##*/}" in
    iotstack)
      if pgrep -af '(/iotstack\.sh|/iotstack) ' >/dev/null 2>&1; then
        echo "ass: iotstack is running -- wait for it to finish" >&2
        return 1
      fi
      ;;
    printstack)
      if pgrep -af '(printstack\.sh|/printstack) ' >/dev/null 2>&1; then
        echo "ass: printstack is running -- wait for it to finish" >&2
        return 1
      fi
      ;;
    wrtstack)
      if pgrep -af 'wrtstack (build|flash)' >/dev/null 2>&1; then
        echo "ass: wrtstack is running -- wait for it to finish" >&2
        return 1
      fi
      ;;
  esac

  return 0
}

# Percent-encode a path for Grok session dirs (~/.grok/sessions/<encoded>/).
_ass_path_urlencode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1" 2>/dev/null
}

# Running Grok session UUIDs bound to this clone (one per line).
_ass_grok_running_session_ids_for_clone() {
  local clone="$1" encoded base entry sid
  clone=$(readlink -f "$clone")
  encoded=$(_ass_path_urlencode "$clone") || return 1
  [[ -n "$encoded" ]] || return 1
  base="${HOME}/.grok/sessions/${encoded}"
  [[ -d "$base" ]] || return 0
  for entry in "$base"/*; do
    [[ -d "$entry" ]] || continue
    sid=$(basename "$entry")
    [[ "$sid" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || continue
    pgrep -f "^grok --resume ${sid}\$" >/dev/null 2>&1 && printf '%s\n' "$sid"
  done
}

# True when a Claude Code process has cwd under the clone.
_ass_claude_running_on_clone() {
  local clone="$1" pid cwd
  clone=$(readlink -f "$clone")
  while IFS= read -r pid; do
    [[ -n "$pid" && "$pid" =~ ^[0-9]+$ ]] || continue
    cwd=$(readlink -f "/proc/${pid}/cwd" 2>/dev/null) || continue
    [[ "$cwd" == "$clone" || "$cwd" == "${clone}/"* ]] && return 0
  done < <(pgrep -x claude 2>/dev/null || true)
  return 1
}

# When an agent session is open on clone: print detail and return 0. Else return 1.
_ass_clone_active_agent_session_detail() {
  local clone="$1" kind sid
  local -a sids=()
  clone=$(readlink -f "$clone")
  kind=$(_ass_session_agent_kind "$clone")

  if [[ "$kind" == grok || "$kind" == "?" ]]; then
    mapfile -t sids < <(_ass_grok_running_session_ids_for_clone "$clone")
    if [[ ${#sids[@]} -gt 0 ]]; then
      sid="${sids[0]}"
      printf 'grok session %s is still open -- quit or close that session first\n' "$sid"
      return 0
    fi
  fi

  if [[ "$kind" == claude || "$kind" == "?" ]]; then
    if _ass_claude_running_on_clone "$clone"; then
      printf 'claude session is still open on this clone -- quit or close that session first\n'
      return 0
    fi
  fi

  return 1
}

# Unix time when init_*_session.sh last aligned this clone (or .git mtime fallback).
_ass_session_init_time() {
  local clone="$1" marker="${clone}/.git/agentstartstack-session-init"

  if [[ -f "$marker" ]]; then
    tr -d '[:space:]' < "$marker"
    return 0
  fi

  stat -c %Y "${clone}/.git" 2>/dev/null || echo 0
}

# Parse ass / ass up args: optional -f/--force, --stashes, -h/--help. Pwd-oriented (no repo name).
# Sets _ASS_PARSE_FORCE (0|1), _ASS_PARSE_STASHES (0|1).
_ass_parse_args() {
  _ASS_PARSE_FORCE=0
  _ASS_PARSE_STASHES=0
  _ASS_PARSE_HELP=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force)
        _ASS_PARSE_FORCE=1
        ;;
      --stashes)
        _ASS_PARSE_STASHES=1
        ;;
      -h|--help|help)
        _ASS_PARSE_HELP=1
        return 0
        ;;
      -*)
        echo "ass sync: unknown option: $1 (try: ass sync help)" >&2
        return 1
        ;;
      *)
        _ass_err "ass sync: unexpected argument: $1 (pwd-oriented -- cd to the repo first)"
        return 1
        ;;
    esac
    shift
  done

  return 0
}

# Echo "ahead behind" for clone HEAD vs canonical main (after local-sync fetch).
_ass_clone_canonical_ahead_behind() {
  local clone="$1" canonical="$2" behind ahead clone_head can_head

  _ass_ensure_local_sync_remote "$clone" "$canonical"
  git -C "$clone" fetch -q local-sync main 2>/dev/null || true
  if read -r behind ahead _ < <(git -C "$clone" rev-list --left-right --count local-sync/main...HEAD 2>/dev/null); then
    printf '%s %s\n' "$ahead" "$behind"
    return 0
  fi
  clone_head=$(git -C "$clone" rev-parse main 2>/dev/null) || { printf '? ?\n'; return 0; }
  can_head=$(git -C "$canonical" rev-parse main 2>/dev/null) || { printf '? ?\n'; return 0; }
  ahead=$(git -C "$canonical" rev-list --count "${can_head}..${clone_head}" 2>/dev/null || printf '?')
  behind=$(git -C "$canonical" rev-list --count "${clone_head}..${can_head}" 2>/dev/null || printf '?')
  printf '%s %s\n' "$ahead" "$behind"
}

# Echo how many commits on canonical main are not in the clone's main.
_ass_clone_behind_canonical() {
  local clone="$1" canonical="$2" _ahead behind
  read -r _ahead behind < <(_ass_clone_canonical_ahead_behind "$clone" "$canonical")
  printf '%s\n' "$behind"
}

# Echo "ahead behind" commit counts for $1's HEAD vs origin/main (after fetch).
_ass_origin_ahead_behind() {
  local repo="$1" behind ahead

  git -C "$repo" fetch -q origin main 2>/dev/null || true
  if read behind ahead _ < <(git -C "$repo" rev-list --left-right --count origin/main...HEAD 2>/dev/null); then
    printf '%s %s\n' "$ahead" "$behind"
    return 0
  fi
  printf '? ?\n'
}

_ass_status_notes() {
  local path="$1" pwd_here="$2"
  local -a notes=()

  [[ "$(readlink -f "$path")" == "$pwd_here" ]] && notes+=("pwd")
  read -r _st_ahead _st_behind < <(_ass_origin_ahead_behind "$path") || true
  [[ "${_st_ahead:-0}" -gt 0 && "${_st_behind:-0}" -gt 0 ]] && notes+=("diverged")
  (IFS=', '; echo "${notes[*]}")
}

# Uncommitted work in the clone not yet in canonical (- or dirty).
_ass_status_wip_column() {
  local clone="$1"
  if _ass_clone_has_dirty_worktree "$clone"; then
    printf 'dirty'
  else
    printf '-'
  fi
}

# Column layout: # agent wip --> | canonical ahead/behind | origin ahead/behind | HEAD path
# --> (after wip): session #1 local-syncs to canonical (data only on row 1).
# Count cols are width 7 (fits git short SHA on the reference row).
_ass_status_format_group_title_row() {
  # shellcheck disable=SC2059
  printf '%-3s %-7s %-7s %-5s %-7s %-7s  %-7s %-7s  %-9s  %s\n' "$@"
}

_ass_status_format_header_row() {
  # shellcheck disable=SC2059
  printf '%-3s %-7s %-7s %-5s %-7s %-7s  %-7s %-7s  %-9s  %s\n' "$@"
}

_ass_status_format_row() {
  # shellcheck disable=SC2059
  printf '%-3s %-7s %-7s %-5s %7s %7s  %7s %7s  %-9s  %s' "$@"
}

# ass status # column: 1 = newest (rollover target); ^ = rolls into #1 on trim/drop.
_ass_status_index_display() {
  local i="$1"
  if [[ "$i" -eq 1 ]]; then
    printf '1'
  else
    printf '^'
  fi
}

_ass_status_print_row() {
  local path="$1" pwd_here="$2" canonical="$3" agent="${4:--}" idx="${5:--}"
  local ahead behind can_ahead can_behind head wip sync_col notes

  read -r ahead behind < <(_ass_origin_ahead_behind "$path")
  read -r can_ahead can_behind < <(_ass_clone_canonical_ahead_behind "$path" "$canonical")
  head=$(git -C "$path" rev-parse --short HEAD 2>/dev/null || echo '?')
  wip=$(_ass_status_wip_column "$path")
  sync_col=""
  [[ "$idx" == "1" ]] && sync_col="-->"
  notes=$(_ass_status_notes "$path" "$pwd_here")

  _ass_status_format_row "$idx" "$agent" "$wip" "$sync_col" "$can_ahead" "$can_behind" \
    "$ahead" "$behind" "$head" "$path"
  [[ -n "$notes" ]] && printf '  (%s)' "$notes"
  printf '\n'
}

# ass status -- agent session clones vs origin/main and canonical/main.
ass_status() {
  local -a _ass_argv clones=()
  local sync_target canonical origin repo_name pwd_here origin_head can_head
  local clone i

  if _ass_help_requested "${1:-}"; then
    ass_help_status
    return 0
  fi

  _as_cli_parse_global_flags _ass_argv "$@" || return 1
  if [[ ${#_ass_argv[@]} -gt 0 ]]; then
    _ass_err "ass status: unexpected argument: ${_ass_argv[0]} (pwd-oriented -- cd to the repo first)"
    return 1
  fi

  sync_target=$(_ass_resolve_sync_target "") || return 1
  canonical=$(readlink -f "$sync_target")
  repo_name=$(basename "$canonical")
  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || {
    _ass_err "ass status: canonical has no origin remote"
    return 1
  }
  pwd_here=$(readlink -f "$(pwd)" 2>/dev/null || pwd)

  git -C "$canonical" fetch -q origin main 2>/dev/null || true
  origin_head=$(git -C "$canonical" rev-parse --short origin/main 2>/dev/null || echo '?')
  can_head=$(git -C "$canonical" rev-parse --short main 2>/dev/null || echo '?')

  _ass_info "ass status: ${repo_name} (agent session clones)"
  _ass_info "vs canonical/main @ ${can_head}  -->  origin/main @ ${origin_head}"
  _ass_info "pwd: ${pwd_here}"
  echo ""
  _ass_status_format_group_title_row "" "" "" "" "canonical" "" "origin/main" "" ""
  _ass_status_format_header_row "#" "agent" "wip" "-->" "ahead" "behind" "ahead" "behind" "HEAD" "path"
  _ass_status_format_header_row "---" "-------" "-------" "-----" "-------" "-------" "-------" "-------" "---------" "----"

  mapfile -t clones < <(agent_session_clones_list "$origin")

  if [[ ${#clones[@]} -eq 0 ]]; then
    echo "agent session clones: (none)"
  else
    i=1
    for clone in "${clones[@]}"; do
      _ass_status_print_row "$clone" "$pwd_here" "$canonical" \
        "$(_ass_session_agent_kind "$clone")" "$(_ass_status_index_display "$i")"
      i=$((i + 1))
    done
  fi

  echo ""
  _ass_info "^ = rolls into #1 on trim/drop (ass list shows numeric index for ass drop)"
  _ass_info "wip = uncommitted work in clone not yet in canonical (dirty or -)"
  _ass_info "--> (after wip) = session #1 local-syncs to canonical (ass sync handoff)"
  _ass_info "1st ahead/behind pair: vs canonical/main @ ${can_head}"
  _ass_info "2nd ahead/behind pair: vs origin/main @ ${origin_head}"
  return 0
}

# Human-readable ahead/behind phrase for ass info summaries.
_ass_info_sync_phrase() {
  local ahead="$1" behind="$2" label="$3"

  if [[ "$ahead" == '?' || "$behind" == '?' ]]; then
    printf 'position vs %s is unknown' "$label"
    return 0
  fi
  if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
    printf 'aligned with %s' "$label"
  elif [[ "$ahead" -gt 0 && "$behind" -eq 0 ]]; then
    printf '%s commit(s) ahead of %s' "$ahead" "$label"
  elif [[ "$ahead" -eq 0 && "$behind" -gt 0 ]]; then
    printf '%s commit(s) behind %s' "$behind" "$label"
  else
    printf '%s ahead and %s behind %s' "$ahead" "$behind" "$label"
  fi
}

# Paragraph describing commits on the clone not yet in canonical.
_ass_info_committed_work_paragraph() {
  local clone="$1" canonical="$2" ahead="$3"
  local -a subjects=()
  local subject_list n

  [[ "$ahead" =~ ^[0-9]+$ && "$ahead" -gt 0 ]] || return 0

  _ass_ensure_local_sync_remote "$clone" "$canonical"
  git -C "$clone" fetch -q local-sync main 2>/dev/null || true
  mapfile -t subjects < <(git -C "$clone" log local-sync/main..HEAD --format='%s' 2>/dev/null | head -8)

  if [[ ${#subjects[@]} -eq 0 ]]; then
    printf 'Committed work not yet in canonical: %s commit(s) on main (details unavailable).' "$ahead"
    return 0
  fi

  subject_list="${subjects[0]}"
  for ((n = 1; n < ${#subjects[@]}; n++)); do
    subject_list+=", ${subjects[n]}"
  done

  if [[ "$ahead" -gt ${#subjects[@]} ]]; then
    printf 'Committed work not yet in canonical (%s commit(s)): %s, and %s more.' \
      "$ahead" "$subject_list" "$((ahead - ${#subjects[@]}))"
  else
    printf 'Committed work not yet in canonical (%s commit(s)): %s.' \
      "$ahead" "$subject_list"
  fi
}

# Paragraph analyzing uncommitted work in the clone worktree.
_ass_info_dirty_work_paragraph() {
  local clone="$1"
  local modified=0 staged=0 deleted=0 untracked=0 renamed=0
  local line status path
  local ins=0 del=0 files=0
  local -a untracked_files=()
  local top_summary stash_n active=0

  [[ -n "$(git -C "$clone" status --porcelain 2>/dev/null)" ]] || return 0

  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    status=${line:0:2}
    path=${line:3}
    case "$status" in
      'M '|'MM'|' M'|'AM') modified=$((modified + 1)) ;;
      'A '|'AA') staged=$((staged + 1)) ;;
      'D '|' D'|'AD') deleted=$((deleted + 1)) ;;
      'R '|'RM') renamed=$((renamed + 1)) ;;
      '??') untracked=$((untracked + 1)); untracked_files+=("$path") ;;
      *) modified=$((modified + 1)) ;;
    esac
  done < <(git -C "$clone" status --porcelain 2>/dev/null)

  read -r ins del files < <(
    {
      git -C "$clone" diff --numstat 2>/dev/null
      git -C "$clone" diff --cached --numstat 2>/dev/null
    } | awk '
      NF >= 2 {
        add = ($1 == "-" ? 0 : $1 + 0)
        rem = ($2 == "-" ? 0 : $2 + 0)
        ins += add
        del += rem
        files++
      }
      END { printf "%d %d %d\n", ins + 0, del + 0, files + 0 }
    '
  )

  top_summary=$(
    {
      git -C "$clone" diff --numstat 2>/dev/null
      git -C "$clone" diff --cached --numstat 2>/dev/null
    } | awk '
      NF >= 2 {
        add = ($1 == "-" ? 0 : $1 + 0)
        rem = ($2 == "-" ? 0 : $2 + 0)
        $1 = $2 = ""
        sub(/^[ \t]+/, "")
        file = $0
        total = add + rem
        if (total > 0 && file != "") printf "%d\t%s\n", total, file
      }
    ' | sort -t$'\t' -k1,1nr | head -5 | awk -F'\t' '{
      printf "%s%s (%s lines)", (n++ ? ", " : ""), $2, $1
    }'
  )

  printf 'Uncommitted work in the worktree'
  local -a parts=()
  [[ "$modified" -gt 0 ]] && parts+=("${modified} modified")
  [[ "$staged" -gt 0 ]] && parts+=("${staged} staged new")
  [[ "$deleted" -gt 0 ]] && parts+=("${deleted} deleted")
  [[ "$renamed" -gt 0 ]] && parts+=("${renamed} renamed")
  [[ "$untracked" -gt 0 ]] && parts+=("${untracked} untracked")
  if [[ ${#parts[@]} -gt 0 ]]; then
    local IFS=', '
    printf ' (%s)' "${parts[*]}"
  fi
  printf ': '

  if [[ "$files" -gt 0 ]]; then
    printf 'tracked diff touches %s insertion(s) and %s deletion(s) across %s file(s)' "$ins" "$del" "$files"
    if [[ -n "$top_summary" ]]; then
      printf '. Largest edits: %s' "$top_summary"
      [[ "$files" -gt 5 ]] && printf ', ...'
    fi
    printf '.'
  elif [[ "$untracked" -gt 0 ]]; then
    printf 'no tracked-line diff; new paths only'
    if [[ ${#untracked_files[@]} -gt 0 ]]; then
      printf ' (e.g. %s' "${untracked_files[0]}"
      [[ ${#untracked_files[@]} -gt 1 ]] && printf ', %s' "${untracked_files[1]}"
      [[ ${#untracked_files[@]} -gt 2 ]] && printf ', ...'
      printf ')'
    fi
    printf '.'
  else
    printf 'worktree is dirty but no line-level diff was produced (check submodules or metadata).'
  fi

  stash_n=$(git -C "$clone" stash list 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$stash_n" -gt 0 ]]; then
    printf ' %s stash entr%s also present.' "$stash_n" "$([[ "$stash_n" -eq 1 ]] && echo y || echo ies)"
  fi

  if _ass_clone_active_agent_session_detail "$clone" >/dev/null 2>&1; then
    active=1
  fi
  if [[ "$active" -eq 1 ]]; then
    printf ' An agent process appears to be active on this clone.'
  fi
}

# ass info -- plain-language summary for one session clone (# from ass status).
ass_info() {
  local -a _ass_argv clones=()
  local index canonical origin repo_name clone agent pwd_here
  local can_ahead can_behind orig_ahead orig_behind head subject head_when
  local init_ts init_when dirty=0 can_phrase orig_phrase p1 p2 work_p2

  if _ass_help_requested "${1:-}"; then
    ass_help_info
    return 0
  fi

  _as_cli_parse_global_flags _ass_argv "$@" || return 1
  if [[ ${#_ass_argv[@]} -ne 1 ]] || ! [[ "${_ass_argv[0]}" =~ ^[0-9]+$ ]]; then
    _ass_err "ass info: usage: ass info <n>  (n from ass status)"
    return 1
  fi
  index="${_ass_argv[0]}"

  canonical=$(_ass_resolve_sync_target "") || return 1
  canonical=$(readlink -f "$canonical")
  repo_name=$(basename "$canonical")
  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || {
    _ass_err "ass info: canonical has no origin remote"
    return 1
  }
  pwd_here=$(readlink -f "$(pwd)" 2>/dev/null || pwd)

  clone=$(_ass_session_clone_at_index "$origin" "$index") || {
    mapfile -t clones < <(agent_session_clones_list "$origin")
    _ass_err "ass info: invalid index: ${index} (${#clones[@]} session clone(s); see: ass status)"
    return 1
  }
  clone=$(readlink -f "$clone")
  agent=$(_ass_session_agent_kind "$clone")

  git -C "$canonical" fetch -q origin main 2>/dev/null || true
  read -r can_ahead can_behind < <(_ass_clone_canonical_ahead_behind "$clone" "$canonical")
  read -r orig_ahead orig_behind < <(_ass_origin_ahead_behind "$clone")
  head=$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || echo '?')
  subject=$(git -C "$clone" log -1 --format='%s' HEAD 2>/dev/null || echo 'unknown')
  head_when=$(git -C "$clone" log -1 --format='%ar' HEAD 2>/dev/null || echo 'unknown')
  _ass_clone_has_dirty_worktree "$clone" && dirty=1

  init_ts=$(_ass_session_init_time "$clone")
  if [[ "$init_ts" =~ ^[0-9]+$ && "$init_ts" -gt 0 ]]; then
    init_when=$(date -d "@${init_ts}" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "epoch ${init_ts}")
  else
    init_when="unknown time"
  fi

  can_phrase=$(_ass_info_sync_phrase "$can_ahead" "$can_behind" "canonical/main")
  orig_phrase=$(_ass_info_sync_phrase "$orig_ahead" "$orig_behind" "origin/main")

  p1="Session #${index} for ${repo_name} is a ${agent} agent clone (initialized ${init_when}). "
  p1+="HEAD ${head} (${subject}, ${head_when}). "
  if [[ "$(readlink -f "$clone")" == "$pwd_here" ]]; then
    p1+="This is your current pwd. "
  fi
  p1+="Sync: ${can_phrase}; ${orig_phrase}."
  if [[ "$dirty" -eq 1 ]]; then
    p1+=" The worktree has uncommitted changes."
  elif [[ "$can_ahead" =~ ^[0-9]+$ && "$can_ahead" -gt 0 ]]; then
    p1+=" The worktree is clean; handoff-ready commits are on main."
  else
    p1+=" The worktree is clean."
  fi

  work_p2=$(_ass_info_committed_work_paragraph "$clone" "$canonical" "$can_ahead")
  if [[ "$dirty" -eq 1 ]]; then
    if [[ -n "$work_p2" ]]; then
      work_p2+=$'\n'
    fi
    work_p2+=$(_ass_info_dirty_work_paragraph "$clone")
  fi

  printf '%s\n' "$p1"
  if [[ -n "$work_p2" ]]; then
    printf '\n%s\n' "$work_p2"
  fi
  return 0
}

# grok / claude / ? -- marker file, then clone dir name, then worktree parent.
_ass_session_agent_kind() {
  local clone="$1" marker kind base
  clone=$(readlink -f "$clone")
  marker="${clone}/.git/agentstartstack-session-agent"
  if [[ -f "$marker" ]]; then
    kind=$(tr -d '[:space:]' < "$marker")
    [[ "$kind" == grok || "$kind" == claude ]] && { printf '%s\n' "$kind"; return 0; }
  fi
  base=$(basename "$clone")
  if [[ "$base" == claude-* ]]; then
    printf 'claude\n'
    return 0
  fi
  if [[ "$base" == grok-* ]]; then
    printf 'grok\n'
    return 0
  fi
  kind=$(_ass_up_trim_harness "$clone")
  [[ "$kind" == grok || "$kind" == claude ]] && { printf '%s\n' "$kind"; return 0; }
  printf '?'
}

# 1-based index into agent_session_clones_list (ass list/status numbering).
_ass_session_clone_at_index() {
  local origin="$1" index="$2"
  local -a clones=()

  [[ "$index" =~ ^[0-9]+$ && "$index" -ge 1 ]] || return 1
  mapfile -t clones < <(agent_session_clones_list "$origin")
  [[ "$index" -le "${#clones[@]}" ]] || return 1
  printf '%s\n' "${clones[index - 1]}"
}

# Newest session clone other than $1 (for dirty-work rollover before drop).
_ass_drop_rollover_survivor() {
  local target="$1"
  shift
  local c

  target=$(readlink -f "$target")
  for c in "$@"; do
    [[ -n "$c" ]] || continue
    c=$(readlink -f "$c")
    [[ "$c" != "$target" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

# ass list -- session clones for the canonical repo at pwd.
ass_list() {
  local -a _ass_argv clones=()
  local canonical origin repo_name pwd_here clone
  local i agent head behind notes

  if _ass_help_requested "${1:-}"; then
    ass_help_list
    return 0
  fi

  _as_cli_parse_global_flags _ass_argv "$@" || return 1
  if [[ ${#_ass_argv[@]} -gt 0 ]]; then
    _ass_err "ass list: unexpected argument: ${_ass_argv[0]} (run from canonical pwd)"
    return 1
  fi

  canonical=$(_ass_resolve_sync_target "") || return 1
  canonical=$(readlink -f "$canonical")
  repo_name=$(basename "$canonical")
  pwd_here=$(readlink -f "$(pwd)" 2>/dev/null || pwd)

  if [[ "$pwd_here" != "$canonical" ]]; then
    _ass_warn "ass list: pwd is not canonical -- listing clones for ${repo_name} anyway"
    _ass_warn "ass list:   canonical: ${canonical}"
    _ass_warn "ass list:   pwd:       ${pwd_here}"
  fi

  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || {
    _ass_err "ass list: canonical has no origin remote"
    return 1
  }

  _ass_info "ass list: ${repo_name}"
  _ass_info "canonical: ${canonical}"

  mapfile -t clones < <(agent_session_clones_list "$origin")

  if [[ ${#clones[@]} -eq 0 ]]; then
    echo "session clones: (none)"
    _ass_info "parent dirs: ${AGENT_SESSION_CLONE_PARENT}"
    return 0
  fi

  echo ""
  printf '%-3s %-7s %-9s %6s  %s\n' "#" "agent" "HEAD" "behind" "path"
  printf '%-3s %-7s %-9s %6s  %s\n' "---" "-------" "---------" "------" "----"

  i=1
  for clone in "${clones[@]}"; do
    agent=$(_ass_session_agent_kind "$clone")
    head=$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || echo '?')
    behind=$(_ass_clone_behind_canonical "$clone" "$canonical")
    notes=""
    if _ass_clone_has_dirty_worktree "$clone"; then notes=" dirty"; fi
    if [[ "$clone" == "$pwd_here" ]]; then notes="${notes} pwd"; fi
    printf '%-3s %-7s %-9s %6s  %s%s\n' "$i" "$agent" "$head" "$behind" "$clone" "$notes"
    i=$((i + 1))
  done

  echo ""
  _ass_info "behind = commits on canonical main not in this clone"
  _ass_info "see also: ass status (vs origin/main)"
  return 0
}

# ass sync all -- align every session clone that is behind canonical.
ass_sync_all() {
  local -a _ass_argv clones=()
  local canonical origin repo_name pwd_here clone script_dir
  local behind ahead synced=0 skipped=0 failed=0 would_sync=0 dry_run=0
  local head can_head

  if _ass_help_requested "${1:-}"; then
    ass_help_sync_all
    return 0
  fi

  _as_cli_parse_global_flags _ass_argv "$@" || return 1
  while [[ ${#_ass_argv[@]} -gt 0 ]]; do
    case "${_ass_argv[0]}" in
      --dry-run) dry_run=1; _ass_argv=("${_ass_argv[@]:1}") ;;
      *)
        _ass_err "ass sync all: unexpected argument: ${_ass_argv[0]}"
        return 1
        ;;
    esac
  done

  canonical=$(_ass_resolve_sync_target "") || return 1
  canonical=$(readlink -f "$canonical")
  repo_name=$(basename "$canonical")
  pwd_here=$(readlink -f "$(pwd)" 2>/dev/null || pwd)
  script_dir="${_ASS_ALIASES_LIB_DIR}/.."

  if [[ "$pwd_here" != "$canonical" ]]; then
    _ass_warn "ass sync all: pwd is not canonical -- syncing clones for ${repo_name} anyway"
    _ass_warn "ass sync all:   canonical: ${canonical}"
    _ass_warn "ass sync all:   pwd:       ${pwd_here}"
  fi

  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || {
    _ass_err "ass sync all: canonical has no origin remote"
    return 1
  }

  can_head=$(git -C "$canonical" rev-parse --short main 2>/dev/null || echo '?')
  _ass_info "ass sync all: ${repo_name} @ ${can_head}"
  _ass_info "canonical: ${canonical}"
  [[ "$dry_run" == 1 ]] && _ass_info "ass sync all: dry-run (no changes)"

  while IFS= read -r clone; do
    [[ -n "$clone" ]] || continue
    clones+=("$(readlink -f "$clone")")
  done < <(agent_session_clones_list "$origin")

  if [[ ${#clones[@]} -eq 0 ]]; then
    _ass_info "ass sync all: no session clones"
    return 0
  fi

  echo ""
  for clone in "${clones[@]}"; do
    behind=$(_ass_clone_behind_canonical "$clone" "$canonical")
    ahead=$(_ass_clone_ahead_of_canonical "$clone" "$canonical")
    head=$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || echo '?')

    if [[ "$behind" == 0 || "$behind" == '?' ]]; then
      if _ass_clone_has_dirty_worktree "$clone"; then
        _ass_info "ass sync all: ${clone}"
        _ass_info "ass sync all:   HEAD ${head}  0 behind  dirty -- would auto-commit only"
        if [[ "$dry_run" == 0 ]]; then
          "${script_dir}/auto-commit-session-work.sh" "$clone" || true
        fi
      else
        _ass_info "ass sync all: ${clone}"
        _ass_info "ass sync all:   HEAD ${head}  already aligned (0 behind)"
      fi
      skipped=$((skipped + 1))
      continue
    fi

    _ass_info "ass sync all: ${clone}"
    _ass_info "ass sync all:   HEAD ${head}  ${behind} behind canonical  ${ahead} ahead"
    if [[ "$dry_run" == 1 ]]; then
      _ass_info "ass sync all:   (dry-run) would fast-forward or rebase onto local-sync/main"
      would_sync=$((would_sync + 1))
      continue
    fi

    if _ass_sync_clone_behind_canonical "$clone" "$canonical"; then
      head=$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || echo '?')
      _ass_ok "ass sync all: aligned ${clone} @ ${head}"
      synced=$((synced + 1))
    else
      _ass_err "ass sync all: failed ${clone} (resolve conflicts or .agentstartstack-bump, then re-run)"
      failed=$((failed + 1))
    fi
  done

  echo ""
  if [[ "$dry_run" == 1 ]]; then
    _ass_info "ass sync all: would_sync=${would_sync} skipped=${skipped}"
  else
    _ass_info "ass sync all: synced=${synced} skipped=${skipped} failed=${failed}"
  fi
  [[ "$failed" -eq 0 ]]
}

# ass sync -- local-sync handoff (session clone -> canonical). Former bare `ass`.
ass_sync() {
  local -a _ass_argv sync_target

  if _ass_help_requested "${1:-}"; then
    ass_help_sync
    return 0
  fi

  _as_cli_parse_global_flags _ass_argv "$@" || return 1

  if [[ "${_ass_argv[0]:-}" == "all" ]]; then
    if _ass_help_requested "${_ass_argv[1]:-}"; then
      ass_help_sync_all
      return 0
    fi
    ass_sync_all "${_ass_argv[@]:1}"
    return $?
  fi

  _ass_parse_args "${_ass_argv[@]}" || return 1
  [[ "$_ASS_PARSE_HELP" == 1 ]] && { ass_help_sync; return 0; }

  sync_target=$(_ass_resolve_sync_target "") || return 1
  _ass_push "$sync_target" "$_ASS_PARSE_FORCE" "$_ASS_PARSE_STASHES"
}

_ass_print_handoff_report() {
  local sync_target="$1" origin_target="$2" repo_name="$3" selected="${4:-}"
  local pwd_here clone head ahead behind sel
  local -a clones=()

  sync_target=$(readlink -f "$sync_target")
  pwd_here=$(readlink -f "$(pwd)" 2>/dev/null || pwd)

  echo "ass: pwd: ${pwd_here}"
  echo "ass: canonical (${repo_name}): ${sync_target}"
  if [[ "$pwd_here" == "$sync_target" ]]; then
    echo "ass: pwd is canonical"
  fi

  while IFS= read -r clone; do
    [[ -n "$clone" ]] || continue
    clones+=("$(readlink -f "$clone")")
  done < <(agent_session_clones_list "$origin_target")

  echo "ass: session clones (${#clones[@]}):"
  if [[ "${#clones[@]}" -eq 0 ]]; then
    echo "ass:   (none)"
    return 0
  fi

  for clone in "${clones[@]}"; do
    head=$(git -C "$clone" log -1 --oneline main 2>/dev/null \
      || git -C "$clone" log -1 --oneline 2>/dev/null \
      || echo "(no commits)")
    ahead=$(_ass_clone_ahead_of_canonical "$clone" "$sync_target")
    behind=$(_ass_clone_behind_canonical "$clone" "$sync_target")
    sel=""
    [[ -n "$selected" && "$clone" == "$(readlink -f "$selected")" ]] \
      && sel="  [selected for handoff]"
    printf 'ass:   %s%s\n' "$clone" "$sel"
    printf 'ass:     HEAD %s  ahead canonical: %s  behind canonical: %s commit(s)\n' \
      "$head" "$ahead" "$behind"
  done
}


# --- ass handoff reconcile + canonical WIP (injected by restore-ass-migration.py) ---

_ass_clone_has_dirty_worktree() {
  local clone="$1"
  [[ -n "$(git -C "$clone" status --porcelain 2>/dev/null)" ]]
}

_ass_ensure_local_sync_remote() {
  local clone="$1" canonical="$2"
  if git -C "$clone" remote get-url local-sync >/dev/null 2>&1; then
    git -C "$clone" remote set-url local-sync "$canonical"
  else
    git -C "$clone" remote add local-sync "$canonical"
  fi
}

_ass_handoff_reconcile_pop_stash() {
  local clone="$1" stashed="$2"
  [[ "$stashed" == 1 ]] || return 0
  _ass_info "ass: restoring stashed session-clone work..."
  if ! git -C "$clone" stash pop; then
    _ass_warn "ass: stash pop left conflicts -- resolve in session clone (git stash list)"
  fi
}

_ass_canonical_apply_stash_entry_to_clone() {
  local canonical="$1" clone="$2" stash_ref="${3:-stash@{0}}"
  git -C "$canonical" stash show "$stash_ref" >/dev/null 2>&1 || return 0
  if git -C "$canonical" stash show -p --include-untracked "$stash_ref" 2>/dev/null \
      | git -C "$clone" apply --3way 2>/dev/null; then
    git -C "$canonical" stash drop "$stash_ref" >/dev/null 2>&1
    return 0
  fi
  if git -C "$canonical" stash show -p "$stash_ref" 2>/dev/null \
      | git -C "$clone" apply --3way 2>/dev/null; then
    git -C "$canonical" stash drop "$stash_ref" >/dev/null 2>&1
    return 0
  fi
  return 1
}

# Everything after "stash@{n}: " on a git stash list line.
_ass_stash_title_from_list_line() {
  local line="$1"
  if [[ "$line" =~ ^stash@[{][0-9]+[}]:[[:space:]](.*)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  printf '%s\n' "$line"
}

# Newest stash@{0} is displayed as 1.
_ass_stash_display_num_from_ref() {
  local ref="$1"
  if [[ "$ref" =~ ^stash@[{]([0-9]+)[}]$ ]]; then
    printf '%s\n' "$((BASH_REMATCH[1] + 1))"
    return 0
  fi
  return 1
}

# User-facing stash number (1-based) -> stash@{n}.
_ass_stash_ref_from_display_num() {
  local num="$1"
  [[ "$num" =~ ^[0-9]+$ ]] || return 1
  [[ "$num" -ge 1 ]] || return 1
  printf 'stash@{%s}\n' "$((num - 1))"
}

_ass_stash_display_label() {
  local canonical="$1" ref="$2"
  local num line title
  num=$(_ass_stash_display_num_from_ref "$ref") || { printf '%s\n' "$ref"; return 0; }
  line=$(git -C "$canonical" stash list 2>/dev/null | grep -F "${ref}:" | head -1)
  title=$(_ass_stash_title_from_list_line "${line:-$ref}")
  printf '%s. %s\n' "$num" "$title"
}

_ass_canonical_normalize_stash_ref() {
  local token="$1" ref
  if [[ "$token" =~ ^stash@[{][0-9]+[}]$ ]]; then
    printf '%s\n' "$token"
    return 0
  fi
  if [[ "$token" =~ ^[0-9]+$ ]]; then
    ref=$(_ass_stash_ref_from_display_num "$token") || return 1
    printf '%s\n' "$ref"
    return 0
  fi
  return 1
}

_ass_clone_agent_kind() {
  _ass_session_agent_kind "$1"
}

_ass_canonical_stash_agent_compat_ok() {
  local canonical="$1" clone="$2" stash_ref="$3"
  local script="${_ASS_ALIASES_LIB_DIR}/../ass-stash-compat-check.sh"
  local reason line confirm label
  label=$(_ass_stash_display_label "$canonical" "$stash_ref")
  [[ -x "$script" ]] || script="${_ASS_ALIASES_LIB_DIR}/../ass-stash-compat-check.sh"
  [[ -f "$script" ]] || {
    _ass_warn "ass: stash compat check script missing -- skipping agent review"
    return 0
  }
  if bash "$script" --clone "$clone" --canonical "$canonical" --stash-ref "$stash_ref"; then
    return 0
  fi
  reason=$(bash "$script" --clone "$clone" --canonical "$canonical" --stash-ref "$stash_ref" 2>&1 || true)
  _ass_warn "ass: session-clone agent advises NO for ${label}:"
  printf '%s\n' "$reason" | while IFS= read -r line; do _ass_warn "ass:   ${line}"; done
  read -r -p "ass: move ${label} anyway? [y/N] " confirm </dev/tty
  [[ "${confirm,,}" == y || "${confirm,,}" == yes ]]
}

_ass_canonical_move_selected_stashes_to_clone() {
  local canonical="$1" clone="$2"
  local selection token ref line moved=0 idx confirm label
  local display_num=1 title
  local -a refs=() indices=()
  if ! git -C "$canonical" stash list 2>/dev/null | grep -q .; then
    return 0
  fi
  _ass_info "ass: canonical git stashes:"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    title=$(_ass_stash_title_from_list_line "$line")
    printf '  %s. %s\n' "$display_num" "$title"
    display_num=$((display_num + 1))
  done < <(git -C "$canonical" stash list 2>/dev/null)
  printf '\n'
  read -r -p "ass: stashes to move (comma/space-separated, e.g. 1 3 or all; empty=none): " selection </dev/tty
  selection="${selection//,/ }"
  if [[ -z "${selection// }" ]]; then
    _ass_info "ass: no stashes selected"
    return 0
  fi
  if [[ "${selection,,}" == "all" ]]; then
    while IFS= read -r line; do
      [[ "$line" =~ ^(stash@[{][0-9]+[}]): ]] || continue
      refs+=("${BASH_REMATCH[1]}")
    done < <(git -C "$canonical" stash list 2>/dev/null)
  else
    for token in $selection; do
      ref=$(_ass_canonical_normalize_stash_ref "$token") || {
        _ass_err "ass: invalid stash number: ${token} (use 1, 2, stash@{0}, or all)"
        return 1
      }
      git -C "$canonical" stash show "$ref" >/dev/null 2>&1 || {
        label=$(_ass_stash_display_label "$canonical" "$ref")
        _ass_err "ass: no such stash: ${label}"
        return 1
      }
      refs+=("$ref")
    done
  fi
  [[ "${#refs[@]}" -eq 0 ]] && { _ass_info "ass: no stashes selected"; return 0; }
  indices=()
  for ref in "${refs[@]}"; do
    idx="${ref#stash@{}"
    idx="${idx%}}"
    indices+=("$idx")
  done
  while IFS= read -r idx; do
    [[ -n "$idx" ]] || continue
    ref="stash@{${idx}}"
    label=$(_ass_stash_display_label "$canonical" "$ref")
    _ass_info "ass: reviewing canonical stash with session-clone agent: ${label}"
    if ! _ass_canonical_stash_agent_compat_ok "$canonical" "$clone" "$ref"; then
      _ass_info "ass: skipped ${label}"
      continue
    fi
    _ass_info "ass: moving canonical stash to session clone: ${label}"
    if _ass_canonical_apply_stash_entry_to_clone "$canonical" "$clone" "$ref"; then
      moved=$((moved + 1))
    else
      _ass_err "ass: failed to apply ${label} to session clone"
      return 1
    fi
  done < <(printf '%s\n' "${indices[@]}" | sort -rn | uniq)
  [[ "$moved" -gt 0 ]] && _ass_ok "ass: moved ${moved} canonical stash(es) to session clone"
  return 0
}

_ass_canonical_move_wip_to_clone() {
  local canonical="$1" clone="$2" handle_stashes="${3:-0}"
  local confirm has_dirty=0 has_stash=0
  [[ "$handle_stashes" == 1 ]] || return 0
  _ass_clone_has_dirty_worktree "$canonical" && has_dirty=1
  git -C "$canonical" stash list 2>/dev/null | grep -q . && has_stash=1
  [[ "$has_dirty" == 1 || "$has_stash" == 1 ]] || return 0
  if [[ "${AS_CLI_QUIET:-0}" -eq 1 ]]; then
    _ass_warn "ass: quiet mode -- not moving canonical WIP to session clone"
    return 0
  fi
  if [[ "$has_dirty" == 1 ]]; then
    _ass_warn "ass: canonical has uncommitted changes"
    confirm=""
    read -r -p "ass: stash uncommitted canonical work? [y/N] " confirm </dev/tty \
      || { _ass_warn "ass: no tty -- leaving uncommitted canonical work in place"; return 0; }
    if [[ "${confirm,,}" != y && "${confirm,,}" != yes ]]; then
      _ass_info "ass: leaving uncommitted canonical work in place"
      [[ "$has_stash" == 0 ]] && return 0
    else
      _ass_info "ass: stashing uncommitted canonical work..."
      git -C "$canonical" stash push -u -m "ass-move-to-session-clone-$(date +%s)" \
        || { _ass_err "ass: failed to stash canonical changes"; return 1; }
    fi
  fi
  _ass_canonical_move_selected_stashes_to_clone "$canonical" "$clone"
}

_ass_clone_ahead_of_canonical() {
  local clone="$1" canonical="$2" ahead _behind
  read -r ahead _behind < <(_ass_clone_canonical_ahead_behind "$clone" "$canonical")
  printf '%s\n' "$ahead"
}

# Canonical must not lag origin/main before handoff; prompt to ff-only merge if it does.
_ass_canonical_assert_not_behind_origin() {
  local canonical="$1" ahead behind confirm

  git -C "$canonical" fetch -q origin main 2>/dev/null || true
  read -r ahead behind < <(_ass_origin_ahead_behind "$canonical")
  if [[ "${behind:-0}" == 0 || "${behind}" == '?' ]]; then
    return 0
  fi

  _ass_warn "ass: canonical is ${behind} commit(s) behind origin/main"
  _ass_warn "ass:   canonical must not lag origin/main"
  read -r -p "ass: merge origin/main into canonical now (ff-only)? [y/N] " confirm </dev/tty \
    || { _ass_err "ass: aborted -- no tty; align canonical with origin/main first"; return 1; }
  if [[ "${confirm,,}" != y && "${confirm,,}" != yes ]]; then
    _ass_err "ass: aborted -- align canonical with origin/main, then re-run ass"
    return 1
  fi
  git -C "$canonical" merge --ff-only origin/main \
    || { _ass_err "ass: ff-only merge of origin/main failed -- reconcile canonical manually"; return 1; }
  _ass_ok "ass: canonical fast-forwarded to origin/main"
  return 0
}

# Auto-commit (if dirty) and reconcile one session clone that is behind canonical.
_ass_sync_clone_behind_canonical() {
  local clone="$1" canonical="$2"
  local behind script_dir="${_ASS_ALIASES_LIB_DIR}/.."

  behind=$(_ass_clone_behind_canonical "$clone" "$canonical")
  [[ "$behind" == 0 || "$behind" == '?' ]] && return 0

  _ass_info "ass: auto-syncing session clone (${behind} behind canonical): ${clone}"
  if _ass_clone_has_dirty_worktree "$clone"; then
    _ass_info "ass: auto-committing dirty work before sync..."
    "${script_dir}/auto-commit-session-work.sh" "$clone" || true
  fi
  _ass_handoff_reconcile_clone "$clone" "$canonical"
}

# Every session clone behind canonical is synced automatically (no prompt).
_ass_auto_sync_all_clones_behind_canonical() {
  local canonical="$1" origin="$2"
  local clone failed=0

  while IFS= read -r clone; do
    [[ -n "$clone" ]] || continue
    if ! _ass_sync_clone_behind_canonical "$clone" "$canonical"; then
      failed=1
    fi
  done < <(agent_session_clones_list "$origin")

  [[ "$failed" -eq 0 ]]
}

# Pick the session clone farthest ahead of canonical (tie: newest commit on main).
_ass_pick_handoff_clone() {
  local canonical="$1" origin="$2" repo_name="$3" force="${4:-0}"
  local nut_last=0 init_time skipped=0
  local candidate best_dir="" best_ahead=-1 best_time=0 ahead t

  if [[ -f "${canonical}/.git/agentstartstack-ass-last" ]]; then
    nut_last=$(tr -d '[:space:]' < "${canonical}/.git/agentstartstack-ass-last")
    [[ "$nut_last" =~ ^[0-9]+$ ]] || nut_last=0
  fi

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue

    if [[ "$force" == 1 && "$nut_last" -gt 0 ]]; then
      init_time=$(_ass_session_init_time "$candidate")
      if [[ "$init_time" -le "$nut_last" ]]; then
        skipped=$((skipped + 1))
        continue
      fi
    fi

    ahead=$(_ass_clone_ahead_of_canonical "$candidate" "$canonical")
    [[ "$ahead" == '?' ]] && continue
    t=$(git -C "$candidate" log -1 --format=%ct 2>/dev/null) || t=0
    if [[ "$ahead" -gt "$best_ahead" ]] \
        || { [[ "$ahead" -eq "$best_ahead" ]] && [[ "$t" -gt "$best_time" ]]; }; then
      best_ahead=$ahead
      best_time=$t
      best_dir=$candidate
    fi
  done < <(agent_session_clones_list "$origin")

  if [[ -z "$best_dir" ]]; then
    if [[ "$force" == 1 && "$nut_last" -gt 0 ]]; then
      echo "ass: --force: no session clone initialized after the last ass for ${repo_name}" >&2
      echo "ass:   last ass: $(date -d "@${nut_last}" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -r "$nut_last" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "@${nut_last}")" >&2
      if [[ "$skipped" -gt 0 ]]; then
        echo "ass:   ignored ${skipped} older session clone(s); align a new session (init_*_session.sh) or omit --force" >&2
      fi
    else
      echo "ass: no session clone for ${repo_name}" >&2
    fi
    return 1
  fi

  if [[ "$force" == 1 && "$skipped" -gt 0 ]]; then
    echo "ass: --force: ignored ${skipped} session clone(s) initialized before last ass" >&2
  fi

  printf '%s\n' "$best_dir"
  return 0
}

_ass_handoff_reconcile_clone() {
  local clone="$1" canonical="$2"
  local ahead behind branch stashed=0
  _ass_ensure_local_sync_remote "$clone" "$canonical"
  git -C "$clone" fetch -q local-sync main \
    || { _ass_err "ass: fetch local-sync/main failed in session clone"; return 1; }
  if _ass_clone_has_dirty_worktree "$clone"; then
    _ass_info "ass: stashing uncommitted session-clone work before reconcile..."
    git -C "$clone" stash push -u -m "ass-handoff-reconcile-$(date +%s)" \
      || { _ass_err "ass: failed to stash uncommitted changes"; return 1; }
    stashed=1
  fi
  if [[ -f "${clone}/.agentstartstack-bump" ]]; then
    _ass_handoff_reconcile_pop_stash "$clone" "$stashed"
    _ass_err "ass: session clone has pending .agentstartstack-bump; apply it before ass"
    return 1
  fi
  ahead=$(_ass_clone_ahead_of_canonical "$clone" "$canonical")
  behind=$(_ass_clone_behind_canonical "$clone" "$canonical")
  if [[ "$behind" == 0 && "$ahead" == 0 ]]; then
    _ass_handoff_reconcile_pop_stash "$clone" "$stashed"
    return 0
  fi
  if [[ "$behind" -gt 0 && "$ahead" == 0 ]]; then
    _ass_info "ass: session clone behind canonical -- fast-forwarding to local-sync/main"
    git -C "$clone" merge --ff-only local-sync/main \
      || { _ass_handoff_reconcile_pop_stash "$clone" "$stashed"; _ass_err "ass: ff-only merge failed"; return 1; }
    _ass_handoff_reconcile_pop_stash "$clone" "$stashed"
    return 0
  fi
  _ass_info "ass: session clone diverged from canonical -- rebasing onto local-sync/main"
  branch=$(git -C "$clone" branch --show-current 2>/dev/null || echo main)
  if ! git -C "$clone" rebase local-sync/main; then
    _ass_handoff_reconcile_pop_stash "$clone" "$stashed"
    _ass_err "ass: rebase conflict -- resolve in session clone, then re-run ass"
    return 1
  fi
  _ass_handoff_reconcile_pop_stash "$clone" "$stashed"
  return 0
}

_ass_handoff_preflight() {
  local clone="$1" canonical="$2"
  local behind
  behind=$(_ass_clone_behind_canonical "$clone" "$canonical")
  [[ "$behind" == 0 || "$behind" == '?' ]] && return 0
  _ass_info "ass: selected clone is ${behind} commit(s) behind canonical -- reconciling"
  _ass_handoff_reconcile_clone "$clone" "$canonical"
}

_ass_push() {
  local sync_target="$1"
  local force="${2:-0}" handle_stashes="${3:-0}"
  local origin_target best_dir="" commit repo_name ahead pushed=0

  sync_target=$(readlink -f "$sync_target")
  [[ -d "${sync_target}/.git" ]] || {
    echo "ass: not a git repo: $sync_target" >&2
    return 1
  }

  _ass_guard_active_sessions "$sync_target" || return 1

  origin_target=$(git -C "$sync_target" remote get-url origin 2>/dev/null) || {
    echo "ass: canonical local repo has no origin remote: $sync_target" >&2
    return 1
  }

  repo_name=$(basename "$sync_target")

  _ass_canonical_assert_not_behind_origin "$sync_target" || return 1
  _ass_auto_sync_all_clones_behind_canonical "$sync_target" "$origin_target" || return 1

  best_dir=$(_ass_pick_handoff_clone "$sync_target" "$origin_target" "$repo_name" "$force") || return 1

  _ass_canonical_move_wip_to_clone "$sync_target" "$best_dir" "$handle_stashes" || return 1
  _ass_handoff_preflight "$best_dir" "$sync_target" || return 1

  ahead=$(_ass_clone_ahead_of_canonical "$best_dir" "$sync_target")
  _ass_print_handoff_report "$sync_target" "$origin_target" "$repo_name" "$best_dir"

  if [[ "$ahead" == 0 ]]; then
    _ass_info "ass: nothing to handoff (no session clone ahead of canonical)"
    return 0
  fi

  if git -C "$best_dir" remote get-url local-sync >/dev/null 2>&1; then
    git -C "$best_dir" remote set-url local-sync "$sync_target"
  else
    git -C "$best_dir" remote add local-sync "$sync_target"
  fi

  commit=$(git -C "$best_dir" log -1 --oneline)
  echo "ass: ${commit}"
  echo "ass: ${best_dir} -> ${sync_target}"
  git -C "$best_dir" push local-sync main
  pushed=1

  date +%s > "${sync_target}/.git/agentstartstack-ass-last"

  # Handoff advances canonical; other session clones may now be behind.
  if [[ "$pushed" == 1 ]]; then
    _ass_auto_sync_all_clones_behind_canonical "$sync_target" "$origin_target" || return 1
  fi
}

_ass_resolve_sync_target() {
  local repo_arg="${1:-}"
  local here sync_target base in_clone

  if [[ -n "$repo_arg" ]]; then
    sync_target=$(_ass_sync_root "$repo_arg") || {
      echo "ass: no canonical local repo found for: ${repo_arg}" >&2
      echo "ass:   set AGENTSTARTSTACK_PROJECT_ROOTS to the dir(s) holding your checkouts" >&2
      return 1
    }
  else
    here=$(git rev-parse --show-toplevel 2>/dev/null) || {
      echo "ass: not in a git repo (pwd-oriented -- cd to the repo first)" >&2
      return 1
    }
    here=$(readlink -f "$here")

    # Is pwd inside one of the agent session-clone parents?
    in_clone=0
    local IFS=:
    for base in ${AGENT_SESSION_CLONE_PARENT}; do
      [[ -n "$base" ]] || continue
      [[ "$here" == "$base"/* ]] && { in_clone=1; break; }
    done
    if [[ "$in_clone" == 1 ]]; then
      sync_target=$(_ass_sync_target_from_worktree "$here") || {
        echo "ass: cannot resolve canonical local repo from: $here" >&2
        return 1
      }
    else
      sync_target="$here"
    fi
  fi

  printf '%s\n' "$(readlink -f "$sync_target")"
}

ass()
{
  local -a _ass_argv
  local arg
  _as_cli_parse_global_flags _ass_argv "$@" || return 1

  for arg in "${_ass_argv[@]}"; do
    case "$arg" in
      -h|--help|help) _ass_main_usage; return 0 ;;
    esac
  done

  if [[ ${#_ass_argv[@]} -eq 0 ]]; then
    _ass_main_usage
    return 0
  fi

  _ass_err "ass: use a subcommand (try: ass help)"
  return 1
}

ass_up()
{
  local -a _ass_argv
  _as_cli_parse_global_flags _ass_argv "$@" || return 1
  set -- "${_ass_argv[@]}"
  if _ass_help_requested "${1:-}"; then
    ass_help_up
    return 0
  fi
  if [[ "${1:-}" == "trim" ]]; then
    shift
    ass_up_trim "$@"
    return $?
  fi

  _ass_parse_args "$@" || return 1

  if [[ "$_ASS_PARSE_HELP" == 1 ]]; then
    ass_help_up
    return 0
  fi

  local sync_target
  sync_target=$(_ass_resolve_sync_target "") || return 1
  _ass_push "$sync_target" "$_ASS_PARSE_FORCE" "$_ASS_PARSE_STASHES" || return 1
  _ass_info "ass up: ${sync_target} -> origin main"
  git -C "$sync_target" push origin main
}

# ass drop (upstream) -- copy generic work from a consumer clone into agentstartstack.
_ass_drop_upstream() {
  local src="$1" dest="${2:-}" here base in_clone=0 as_origin abs_src rel
  local best="" best_t=0 cand t target session_guid desc ledger

  here=$(git rev-parse --show-toplevel 2>/dev/null) || {
    _ass_err "ass drop: not in a git repo"
    return 1
  }
  here=$(readlink -f "$here")

  local IFS=:
  for base in ${AGENT_SESSION_CLONE_PARENT}; do
    [[ -n "$base" ]] || continue
    [[ "$here" == "$base"/* ]] && { in_clone=1; break; }
  done
  unset IFS
  if [[ "$in_clone" != 1 ]]; then
    _ass_err "ass drop: upstream drop runs only from a consumer session clone"
    return 1
  fi

  as_origin=$(git -C "${here}/.agentstartstack" remote get-url origin 2>/dev/null) || {
    _ass_err "ass drop: no .agentstartstack submodule here -- not a consumer clone"
    return 1
  }

  abs_src=$(readlink -f "$src" 2>/dev/null) || { _ass_err "ass drop: not found: $src"; return 1; }
  [[ -e "$abs_src" ]] || { _ass_err "ass drop: not found: $src"; return 1; }
  case "$abs_src" in
    "$here"/*) rel="${abs_src#"${here}/"}" ;;
    *) _ass_err "ass drop: <src> must be inside this clone: $abs_src"; return 1 ;;
  esac
  [[ -n "$dest" ]] || dest="$rel"

  while IFS= read -r cand; do
    [[ -n "$cand" ]] || continue
    [[ "$cand" == "$here" ]] && continue
    t=$(git -C "$cand" log -1 --format=%ct 2>/dev/null) || continue
    if [[ "$t" -gt "$best_t" ]]; then
      best_t=$t
      best="$cand"
    fi
  done < <(agent_session_clones_list "$as_origin")

  if [[ -z "$best" ]]; then
    _ass_err "ass drop: no agentstartstack session clone found (origin: $as_origin)"
    _ass_err "ass drop:   create one (ass new from agentstartstack canonical) and retry"
    return 1
  fi

  target="${best}/${dest}"
  mkdir -p "$(dirname "$target")"
  cp -r "$abs_src" "$target"

  session_guid=$(basename "$here")
  desc="$(basename "$src")"
  ledger="${here}/.agentstartstack-dropits"

  if [[ -f "$target" ]]; then
    if ! grep -q '^Dropit-Id:' "$target" 2>/dev/null; then
      { printf 'Dropit-Id: %s\n\n' "$session_guid"; cat "$target"; } > "${target}.dropit-tmp"
      mv "${target}.dropit-tmp" "$target"
    fi
  else
    _ass_warn "ass drop: multi-file drop; ensure each file carries Dropit-Id: ${session_guid}"
  fi

  if [[ -f "$ledger" ]] && grep -qF "$session_guid" "$ledger" 2>/dev/null; then
    _ass_warn "ass drop: ledger already lists ${session_guid} in ${ledger}"
  else
    printf '%s  %s\n' "$session_guid" "$desc" >> "$ledger"
    _ass_info "ass drop: recorded ${session_guid} in ${ledger} (commit this file in the consumer)"
  fi

  _ass_info "ass drop: ${rel}  ->  ${best}/${dest}"
  _ass_info "ass drop: review + commit in the agentstartstack clone, then ass sync."
  return 0
}

# Archive and remove one session clone; roll dirty work into survivor when set.
_ass_drop_session_clone() {
  local clone="$1" survivor="$2" canonical="$3"
  local archive_dir detail

  clone=$(readlink -f "$clone")
  [[ -n "$survivor" ]] && survivor=$(readlink -f "$survivor")

  if ! _agent_session_clone_is_valid "$clone" "$(git -C "$canonical" remote get-url origin 2>/dev/null)"; then
    _ass_err "ass drop: not a session clone (nested .agentstartstack submodule?)"
    _ass_err "ass drop:   ${clone}"
    _ass_err "ass drop: session clones have a .git directory; see: ass list"
    return 1
  fi

  if detail=$(_ass_clone_active_agent_session_detail "$clone"); then
    _ass_err "ass drop: cannot remove clone with an active agent session"
    while IFS= read -r line; do
      [[ -n "$line" ]] && _ass_err "ass drop:   ${line}"
    done <<<"$detail"
    _ass_err "ass drop:   ${clone}"
    return 1
  fi

  if _ass_up_trim_clone_unlanded "$clone" "$canonical"; then
    _ass_err "ass drop: clone has unlanded commits -- cherry-pick or ass handoff first"
    _ass_err "ass drop:   ${clone}"
    return 1
  fi

  if _ass_up_trim_clone_dirty "$clone"; then
    if [[ -z "$survivor" ]]; then
      _ass_err "ass drop: only session clone and dirty -- commit or clear work first"
      _ass_err "ass drop:   ${clone}"
      return 1
    fi
    _ass_info "ass drop: consolidating dirty work -> ${survivor}"
    read -r _f _c < <(_ass_up_trim_rollover "$clone" "$survivor")
  fi

  archive_dir=$(_ass_up_trim_resolve_archive_dir "$canonical" "")
  _ass_up_trim_archive_clone "$clone" "$archive_dir" 0 \
    || { _ass_err "ass drop: archive failed -- clone left in place"; return 1; }
  return 0
}

# ass drop (no args) -- archive every session clone except #1 (collapse into one).
_ass_drop_all() {
  local canonical origin repo_name pwd_here survivor
  local -a clones=()
  local clone agent head idx line

  canonical=$(_ass_resolve_sync_target "") || return 1
  canonical=$(readlink -f "$canonical")
  repo_name=$(basename "$canonical")
  pwd_here=$(readlink -f "$(pwd)" 2>/dev/null || pwd)

  if [[ "$pwd_here" != "$canonical" ]]; then
    _ass_warn "ass drop: pwd is not canonical -- dropping clones for ${repo_name} anyway"
    _ass_warn "ass drop:   canonical: ${canonical}"
    _ass_warn "ass drop:   pwd:       ${pwd_here}"
  fi

  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || {
    _ass_err "ass drop: canonical has no origin remote"
    return 1
  }

  mapfile -t clones < <(agent_session_clones_list "$origin")
  if [[ ${#clones[@]} -eq 0 ]]; then
    _ass_info "ass drop: no session clones for ${repo_name}"
    return 0
  fi
  if [[ ${#clones[@]} -eq 1 ]]; then
    _ass_info "ass drop: one session clone already (#1) -- nothing to drop"
    return 0
  fi

  survivor=$(readlink -f "${clones[0]}")
  agent=$(_ass_session_agent_kind "$survivor")
  head=$(git -C "$survivor" rev-parse --short HEAD 2>/dev/null || echo '?')
  _ass_info "ass drop: keeping #1 ${agent} @ ${head}"
  _ass_info "ass drop:   ${survivor}"
  _ass_info "ass drop: removing ${#clones[@]} other session clone(s)"

  read -r -p "ass drop: remove $(( ${#clones[@]} - 1 )) session clone(s), keep #1? [y/N] " line
  [[ "$line" == [yY] || "$line" == [yY][eE][sS] ]] || {
    _ass_info "ass drop: aborted"
    return 1
  }

  for ((idx=${#clones[@]}-1; idx>=1; idx--)); do
    clone=$(readlink -f "${clones[idx]}")
    agent=$(_ass_session_agent_kind "$clone")
    head=$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || echo '?')
    _ass_info "ass drop: #$((idx + 1)) ${agent} @ ${head}"
    _ass_info "ass drop:   ${clone}"
    _ass_drop_session_clone "$clone" "$survivor" "$canonical" || return 1
    dropped=$((dropped + 1))
    _ass_ok "ass drop: removed #$((idx + 1)) (${agent})"
  done

  _ass_ok "ass drop: collapsed to one session clone (#1)"
  return 0
}

# ass drop -- archive session clone(s), or copy generic work upstream (consumer pwd).
ass_drop() {
  local -a _ass_argv clones=()
  local index canonical origin repo_name pwd_here clone survivor
  local agent head

  if _ass_help_requested "${1:-}"; then
    ass_help_drop
    return 0
  fi

  _as_cli_parse_global_flags _ass_argv "$@" || return 1
  if [[ ${#_ass_argv[@]} -eq 0 ]]; then
    _ass_drop_all
    return $?
  fi
  if [[ ${#_ass_argv[@]} -le 2 && ! "${_ass_argv[0]}" =~ ^[0-9]+$ ]]; then
    _ass_drop_upstream "${_ass_argv[@]}"
    return $?
  fi
  if [[ ${#_ass_argv[@]} -ne 1 ]]; then
    _ass_err "ass drop: usage: ass drop | ass drop <n> | ass drop <src> [<dest>]"
    return 1
  fi
  index="${_ass_argv[0]}"
  if ! [[ "$index" =~ ^[0-9]+$ ]]; then
    _ass_err "ass drop: invalid index: ${index} (see: ass list)"
    return 1
  fi

  canonical=$(_ass_resolve_sync_target "") || return 1
  canonical=$(readlink -f "$canonical")
  repo_name=$(basename "$canonical")
  pwd_here=$(readlink -f "$(pwd)" 2>/dev/null || pwd)

  if [[ "$pwd_here" != "$canonical" ]]; then
    _ass_warn "ass drop: pwd is not canonical -- dropping clone for ${repo_name} anyway"
    _ass_warn "ass drop:   canonical: ${canonical}"
    _ass_warn "ass drop:   pwd:       ${pwd_here}"
  fi

  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || {
    _ass_err "ass drop: canonical has no origin remote"
    return 1
  }

  clone=$(_ass_session_clone_at_index "$origin" "$index") || {
    mapfile -t clones < <(agent_session_clones_list "$origin")
    _ass_err "ass drop: invalid index: ${index} (${#clones[@]} session clone(s); see: ass list)"
    return 1
  }
  clone=$(readlink -f "$clone")

  mapfile -t clones < <(agent_session_clones_list "$origin")
  agent=$(_ass_session_agent_kind "$clone")
  head=$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || echo '?')

  _ass_info "ass drop: #${index} ${agent} @ ${head}"
  _ass_info "ass drop:   ${clone}"

  survivor=$(_ass_drop_rollover_survivor "$clone" "${clones[@]}") || survivor=""
  _ass_drop_session_clone "$clone" "$survivor" "$canonical" || return 1
  _ass_ok "ass drop: removed #${index} (${agent})"
  return 0
}

# True when ass new runs inside a Codium (VSCodium) integrated terminal.
_ass_in_codium_integrated_terminal() {
  [[ "${TERM_PROGRAM:-}" == vscode ]] || return 1

  local ipc="${VSCODE_IPC_HOOK_CLI:-}" git_node="${VSCODE_GIT_ASKPASS_NODE:-}"
  case "${ipc}${git_node}" in
    *[Cc]odium*|*/codium/*) return 0 ;;
  esac

  local pid="${PPID:-}" depth=0 comm
  while [[ "$depth" -lt 8 && -n "$pid" && "$pid" -gt 1 ]]; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ') || break
    case "$comm" in
      codium|codium-bin|Codium) return 0 ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || break
    depth=$((depth + 1))
  done
  return 1
}

# Leftmost connected output from xrandr: X Y WIDTH HEIGHT.
_ass_codium_left_monitor_geometry() {
  local line x y w h
  command -v xrandr >/dev/null 2>&1 || return 1
  line=$(xrandr --query 2>/dev/null | awk '
    $2 == "connected" {
      if (match($0, /([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)/, m)) {
        printf "%d %d %d %d\n", m[3], m[4], m[1], m[2]
      }
    }
  ' | sort -n -k1,1 | head -1)
  [[ -n "$line" ]] || return 1
  read -r x y w h <<<"$line"
  printf '%s %s %s %s\n' "$x" "$y" "$w" "$h"
}

# Prompt to install wmctrl when missing (Codium window placement on XWayland).
_ass_ensure_wmctrl() {
  local line
  command -v wmctrl >/dev/null 2>&1 && return 0

  _ass_info "wmctrl is not installed (places the new Codium window on the left monitor)"
  read -r -p "ass new: install wmctrl now? [y/N] " line </dev/tty
  [[ "$line" == [yY] || "$line" == [yY][eE][sS] ]] || return 1

  if command -v apt-get >/dev/null 2>&1; then
    if sudo apt-get install -y wmctrl; then
      _ass_ok "ass new: installed wmctrl"
      return 0
    fi
    _ass_err "ass new: wmctrl install failed (try: sudo apt install wmctrl)"
    return 1
  fi

  _ass_err "ass new: apt-get not found; install wmctrl manually for window placement"
  return 1
}

# Best-effort: move a new Codium window to the left monitor and maximize (wmctrl/XWayland).
_ass_codium_place_window_maximized() {
  local marker="$1" x="${2:-0}" y="${3:-0}"
  local wid attempt

  command -v wmctrl >/dev/null 2>&1 || return 1
  for attempt in $(seq 1 40); do
    sleep 0.25
    wid=$(wmctrl -l 2>/dev/null | grep -iF "$marker" | tail -1 | awk '{print $1}') || true
    [[ -n "$wid" ]] || continue
    wmctrl -i -r "$wid" -e "0,${x},${y},-1,-1" 2>/dev/null || true
    wmctrl -i -r "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null && return 0
  done
  return 1
}

# Detached Codium window on the left monitor (maximized) + Claude Code extension.
_ass_open_claude_code_in_codium() {
  local clone_path="$1" marker x=0 y=0

  command -v codium >/dev/null 2>&1 || return 1
  _ass_ensure_wmctrl || _ass_info "ass new: continuing without wmctrl (Electron flags only)"
  marker=$(basename "$clone_path")

  if read -r x y _ _ < <(_ass_codium_left_monitor_geometry 2>/dev/null); then
    :
  fi
  x="${ASS_CODIUM_WINDOW_X:-$x}"
  y="${ASS_CODIUM_WINDOW_Y:-$y}"

  # -n: new detached window. Electron passthrough: position + maximize on that monitor.
  codium -n --window-position="${x},${y}" --start-maximized "$clone_path" >/dev/null 2>&1 \
    || codium -n "$clone_path" >/dev/null 2>&1 \
    || return 1

  _ass_codium_place_window_maximized "$marker" "$x" "$y" &

  sleep 1
  codium -r "vscode://anthropic.claude-code/open" >/dev/null 2>&1 &
  return 0
}

# Infer session agent from installed CLIs: grok only -> grok; claude only -> claude;
# both -> claude. Codium integrated terminal -> claude. Explicit flags override.
_ass_detect_installed_agent() {
  local has_grok=0 has_claude=0
  command -v grok >/dev/null 2>&1 && has_grok=1
  command -v claude >/dev/null 2>&1 && has_claude=1
  if [[ "$has_grok" == 1 && "$has_claude" == 1 ]]; then
    printf 'claude\n'
    return 0
  fi
  if [[ "$has_claude" == 1 ]]; then
    printf 'claude\n'
    return 0
  fi
  if [[ "$has_grok" == 1 ]]; then
    printf 'grok\n'
    return 0
  fi
  return 1
}

# Write gitignored .agentstartstack.env into a session clone so init_* can align it.
_ass_new_write_clone_env() {
  local canonical="$1" clone_path="$2" origin="$3"
  local env_file="${clone_path}/.agentstartstack.env" project_name

  project_name="$(basename "$canonical")"
  if [[ -f "${canonical}/.agentstartstack.env" ]]; then
    cp "${canonical}/.agentstartstack.env" "$env_file"
    # Ensure CANONICAL_LOCAL_REPO points at the real canonical checkout.
    if grep -q '^CANONICAL_LOCAL_REPO=' "$env_file" 2>/dev/null; then
      sed -i "s|^CANONICAL_LOCAL_REPO=.*|CANONICAL_LOCAL_REPO=${canonical}|" "$env_file"
    else
      printf 'CANONICAL_LOCAL_REPO=%s\n' "$canonical" >> "$env_file"
    fi
  else
    cat > "$env_file" <<EOF
PROJECT_NAME=${project_name}
DISPLAY_NAME=${project_name}
CANONICAL_LOCAL_REPO=${canonical}
ORIGIN_URL=${origin}
EOF
  fi
  local parents
  parents=$(_agent_session_clone_parents_default)
  if grep -q '^AGENT_SESSION_CLONE_PARENT=' "$env_file" 2>/dev/null; then
    sed -i "s|^AGENT_SESSION_CLONE_PARENT=.*|AGENT_SESSION_CLONE_PARENT=${parents}|" "$env_file"
  else
    printf 'AGENT_SESSION_CLONE_PARENT=%s\n' "${parents}" >> "$env_file"
  fi
}

ass_new() {
  local agent="" canonical origin session_id clone_path script_dir repo_name
  if _ass_help_requested "${1:-}"; then
    ass_help_new
    return 0
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --grok) agent=grok; shift ;;
      --claude) agent=claude; shift ;;
      *) _ass_err "ass new: unknown option: $1"; return 1 ;;
    esac
  done
  if [[ -z "$agent" ]]; then
    if _ass_in_codium_integrated_terminal; then
      agent=claude
      _ass_info "ass new: using claude (Codium integrated terminal)"
    else
      agent=$(_ass_detect_installed_agent) || {
        _ass_err "ass new: no grok or claude CLI on PATH (install one, or pass --grok/--claude)"
        return 1
      }
      _ass_info "ass new: using ${agent} (inferred from installed CLIs)"
    fi
  fi
  canonical=$(git rev-parse --show-toplevel 2>/dev/null) || {
    _ass_err "ass new: run from the canonical local repo"; return 1
  }
  canonical=$(readlink -f "$canonical")
  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || {
    _ass_err "ass new: canonical has no origin remote"; return 1
  }
  repo_name=$(basename "$canonical")
  session_id=$(date +%s)
  clone_path="${ASS_NEW_SESSION_CLONE_ROOT}/${repo_name}/${session_id}"
  mkdir -p "$(dirname "$clone_path")"
  git clone "$origin" "$clone_path"
  _ass_new_write_clone_env "$canonical" "$clone_path" "$origin"
  script_dir="${_ASS_ALIASES_LIB_DIR}/.."
  "${script_dir}/init_agent_session.sh" "--${agent}" "$clone_path"
  _ass_ok "ass new: session clone ready: ${clone_path}"
  if [[ "$agent" == claude ]] && _ass_in_codium_integrated_terminal; then
    if _ass_open_claude_code_in_codium "$clone_path"; then
      _ass_ok "ass new: opened ${clone_path} in a new Codium window (left monitor, maximized)"
    else
      _ass_info "Open agent session: cd ${clone_path} (codium CLI not found -- open folder manually)"
    fi
  elif [[ "$agent" == grok ]]; then
    _ass_info "Open agent session: cd ${clone_path}"
    _ass_info "Grok/Cursor: open that folder or paste the path above as the session workspace"
  else
    _ass_info "Open agent session: cd ${clone_path}"
    _ass_info "Claude Code: cd there, then start claude in that directory"
  fi
}

# ass up trim -- consolidate and prune stale agent session clones for a consumer.
# See docs/ass.md and workflow.md.

_ass_up_trim_load_env() {
  local canonical="$1" env_file="${canonical}/.agentstartstack.env"
  PROJECT_NAME="$(basename "$canonical")"
  ACTIVE_GUARD_PGREP=""
  AGENTSTARTSTACK_CLONE_ARCHIVE_DIR=""
  ASS_UP_ALL_AUTOTRIM=1
  [[ -f "$env_file" ]] || return 0
  # shellcheck source=/dev/null
  source "$env_file"
  return 0
}

_ass_up_trim_autotrim_enabled() {
  local canonical="$1"
  _ass_up_trim_load_env "$canonical"
  [[ "${ASS_UP_ALL_AUTOTRIM:-1}" != "0" ]]
}

_ass_up_trim_guard() {
  local canonical="$1" name="$2"
  _ass_up_trim_load_env "$canonical" || return 1
  if [[ -n "${ACTIVE_GUARD_PGREP:-}" ]] \
     && pgrep -af "$ACTIVE_GUARD_PGREP" >/dev/null 2>&1; then
    echo "ass up trim: ${name} CLI active (ACTIVE_GUARD_PGREP) -- skipping" >&2
    return 1
  fi
  _ass_guard_active_sessions "$canonical" || return 1
}

_ass_up_trim_clone_mtime() {
  stat -c %Y "$1/.git" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

_ass_up_trim_clone_dirty() {
  [[ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]]
}

_ass_up_trim_clone_unlanded() {
  local clone="$1" canonical="$2" head
  head=$(git -C "$clone" rev-parse HEAD 2>/dev/null) || return 1
  git -C "$canonical" fetch -q origin 2>/dev/null || true
  ! git -C "$canonical" merge-base --is-ancestor "$head" origin/main 2>/dev/null
}

_ass_up_trim_harness() {
  local clone="$1" parents base
  parents="${AGENT_SESSION_CLONE_PARENT}"
  clone=$(readlink -f "$clone")
  local IFS=:
  for base in $parents; do
    [[ -n "$base" ]] || continue
    if [[ "$clone" == "$base"/* ]]; then
      case "$base" in
        */.ass/worktrees) printf 'ass'; return 0 ;;
        */.claude/worktrees) printf 'claude'; return 0 ;;
        */.grok/worktrees) printf 'grok'; return 0 ;;
        *claude*) printf 'claude'; return 0 ;;
        *grok*) printf 'grok'; return 0 ;;
      esac
    fi
  done
  printf 'agent'
}

_ass_up_trim_resolve_archive_dir() {
  local canonical="$1" override="$2" name
  _ass_up_trim_load_env "$canonical"
  name="${PROJECT_NAME:-$(basename "$canonical")}"
  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  if [[ -n "${AGENTSTARTSTACK_CLONE_ARCHIVE_DIR:-}" ]]; then
    printf '%s\n' "${AGENTSTARTSTACK_CLONE_ARCHIVE_DIR}"
    return 0
  fi
  printf '%s\n' "${HOME}/.agentstartstack/archives/${name}/agent_clones"
}

_ass_up_trim_rollover() {
  local old="$1" target="$2"
  local stash_sha patch relpath files=0 conflicts=0 tracked untracked

  stash_sha=$(git -C "$old" stash create --include-untracked 2>/dev/null) || stash_sha=""
  if [[ -n "$stash_sha" ]]; then
    mapfile -t tracked < <(git -C "$old" diff --name-only HEAD 2>/dev/null)
    mapfile -t untracked < <(git -C "$old" ls-files --others --exclude-standard 2>/dev/null)
    files=$((${#tracked[@]} + ${#untracked[@]}))
    if ! git -C "$target" stash apply "$stash_sha" 2>/dev/null; then
      conflicts=1
    fi
    if [[ -n "$(git -C "$target" diff --name-only --diff-filter=U 2>/dev/null)" ]]; then
      conflicts=1
    fi
    if [[ -n "$(find "$target" -name '*.rej' -print -quit 2>/dev/null)" ]]; then
      conflicts=1
    fi
    printf '%s %s\n' "$files" "$conflicts"
    return 0
  fi

  patch=$(mktemp "${TMPDIR:-/tmp}/ass-up-trim-patch.XXXXXX")
  git -C "$old" diff HEAD > "$patch"
  if [[ -s "$patch" ]]; then
    if git -C "$target" apply --3way "$patch" 2>/dev/null; then
      files=$(grep -c '^diff --git' "$patch" 2>/dev/null || echo 0)
    else
      git -C "$target" apply --reject "$patch" 2>/dev/null || true
      conflicts=1
    fi
  fi
  rm -f "$patch"

  while IFS= read -r relpath; do
    [[ -n "$relpath" ]] || continue
    mkdir -p "$(dirname "${target}/${relpath}")"
    if [[ -e "${target}/${relpath}" ]]; then
      conflicts=1
    else
      cp -n "$old/$relpath" "${target}/${relpath}" 2>/dev/null \
        || { cp "$old/$relpath" "${target}/${relpath}"; conflicts=1; }
      files=$((files + 1))
    fi
  done < <(git -C "$old" ls-files --others --exclude-standard 2>/dev/null)

  printf '%s %s\n' "$files" "$conflicts"
}

# Kept set = --keep-latest N clones by mtime, plus pwd session clone when invoked from one.
# Rollover target = newest-by-mtime clone in the kept set.
_ass_up_trim_build_kept_set() {
  local keep_latest="$1" invoked_from="$2"
  shift 2
  local -a all_clones_list=("$@")
  local -a kept=() sorted=()
  local clone mtime best_mtime=0 rollover_target="" t

  mapfile -t sorted < <(
    for clone in "${all_clones_list[@]}"; do
      printf '%s %s\n' "$(_ass_up_trim_clone_mtime "$clone")" "$clone"
    done | sort -rn -k1,1 | awk '{print $2}'
  )

  t=0
  for clone in "${sorted[@]}"; do
    [[ "$t" -ge "$keep_latest" ]] && break
    _ass_up_trim_kept_contains "$clone" "${kept[@]}" || kept+=("$clone")
    t=$((t + 1))
  done

  if [[ -n "$invoked_from" ]] \
     && ! _ass_up_trim_kept_contains "$invoked_from" "${kept[@]}"; then
    kept+=("$invoked_from")
  fi

  for clone in "${kept[@]}"; do
    mtime=$(_ass_up_trim_clone_mtime "$clone")
    if [[ "$mtime" -ge "$best_mtime" ]]; then
      best_mtime=$mtime
      rollover_target="$clone"
    fi
  done

  printf '%s\n' "$rollover_target"
  for clone in "${kept[@]}"; do
    printf '%s\n' "$clone"
  done
}

_ass_up_trim_archive_clone() {
  local clone="$1" archive_dir="$2" dry_run="$3"
  local parent base harness shortsha datestamp dest tarball detail

  clone=$(readlink -f "$clone")
  parent=$(dirname "$clone")
  base=$(basename "$clone")
  [[ -d "${clone}/.git" ]] || {
    echo "ass up trim:   ERROR ${clone} has no .git directory -- refusing" >&2
    return 1
  }

  if detail=$(_ass_clone_active_agent_session_detail "$clone"); then
    echo "ass up trim:   ERROR active agent session on ${clone}" >&2
    while IFS= read -r line; do
      [[ -n "$line" ]] && echo "ass up trim:     ${line}" >&2
    done <<<"$detail"
    return 1
  fi

  harness=$(_ass_up_trim_harness "$clone")
  shortsha=$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || echo unknown)
  datestamp=$(date +%Y%m%d)
  dest="${archive_dir}/${harness}-${base}-${shortsha}-${datestamp}.tar.gz"

  if [[ "$dry_run" == 1 ]]; then
    echo "ass up trim:   [dry-run] prune ${clone} -> ${dest}"
    echo "ass up trim:   [dry-run] rm -rf ${clone}"
    return 0
  fi

  mkdir -p "$archive_dir"
  tarball="$dest"
  if ! tar czf "$tarball" -C "$parent" "$base"; then
    echo "ass up trim:   ERROR archiving ${clone}" >&2
    return 1
  fi
  if ! tar tzf "$tarball" >/dev/null 2>&1; then
    echo "ass up trim:   ERROR verifying ${tarball} -- source left in place" >&2
    rm -f "$tarball"
    return 1
  fi
  # HARD RULE (docs/workflow.md): session clones may only be removed after verified archive.
  [[ -f "$tarball" ]] || {
    echo "ass up trim:   ERROR missing archive ${tarball} -- refusing rm" >&2
    return 1
  }
  rm -rf "$clone"
  echo "ass up trim:   pruned ${clone} -> ${tarball}"
  return 0
}

_ass_up_trim_resolve_invoked_from() {
  local canonical="$1" here in_clone=0 base
  here=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  here=$(readlink -f "$here")
  local IFS=:
  for base in ${AGENT_SESSION_CLONE_PARENT}; do
    [[ -n "$base" ]] || continue
    [[ "$here" == "$base"/* ]] && { in_clone=1; break; }
  done
  unset IFS
  [[ "$in_clone" == 1 ]] || return 0
  if [[ "$(_ass_sync_target_from_worktree "$here" 2>/dev/null || true)" == "$(readlink -f "$canonical")" ]]; then
    printf '%s\n' "$here"
  fi
}

_ass_up_trim_kept_contains() {
  local needle="$1" k
  shift
  for k in "$@"; do
    [[ "$k" == "$needle" ]] && return 0
  done
  return 1
}

_ass_up_trim_one() {
  local name="$1" dry_run="$2" yes="$3" no_rollover="$4" keep_latest="$5" archive_override="$6"
  local canonical archive_dir invoked_from rollover_target detail
  local -a all_clones_list=() kept=() to_archive=() kept_lines=()
  local clone mtime dirty unlanded archived=0 rolled=0 kept_unlanded=0 kept_dirty=0
  local kept_current=0 files conflicts subjects line reason pwd_here head markers
  local tarball_dest harness shortsha datestamp base

  canonical=$(_ass_sync_root "$name") || {
    echo "ass up trim: no canonical local repo for: ${name}" >&2
    return 1
  }
  canonical=$(readlink -f "$canonical")

  _ass_up_trim_guard "$canonical" "$name" || return 1

  archive_dir=$(_ass_up_trim_resolve_archive_dir "$canonical" "$archive_override")
  invoked_from=$(_ass_up_trim_resolve_invoked_from "$canonical" || true)

  while IFS= read -r clone; do
    [[ -n "$clone" ]] || continue
    all_clones_list+=("$(readlink -f "$clone")")
  done < <(_ass_session_clones_for_consumer "$name")

  if [[ "${#all_clones_list[@]}" -eq 0 ]]; then
    echo "ass up trim: ${name} -- no session clones found"
    return 0
  fi

  mapfile -t kept_lines < <(_ass_up_trim_build_kept_set "$keep_latest" "$invoked_from" \
    "${all_clones_list[@]}")
  rollover_target="${kept_lines[0]:-}"
  kept=()
  if [[ ${#kept_lines[@]} -gt 1 ]]; then
    kept=("${kept_lines[@]:1}")
  fi

  to_archive=()
  for clone in "${all_clones_list[@]}"; do
    _ass_up_trim_kept_contains "$clone" "${kept[@]}" && continue
    to_archive+=("$clone")
  done
  mapfile -t to_archive < <(
    for clone in "${to_archive[@]}"; do
      printf '%s %s\n' "$(_ass_up_trim_clone_mtime "$clone")" "$clone"
    done | sort -n -k1,1 | awk '{print $2}'
  )

  git -C "$canonical" fetch -q origin 2>/dev/null || true

  pwd_here=$(readlink -f "$(pwd)" 2>/dev/null || pwd)
  echo "ass up trim: pwd: ${pwd_here}"
  echo "ass up trim: canonical (${name}): ${canonical}"
  if [[ "$pwd_here" == "$canonical" ]]; then
    echo "ass up trim: pwd is canonical (expected)"
  elif [[ -n "$invoked_from" ]]; then
    echo "ass up trim: pwd session clone: ${invoked_from}"
  fi
  echo "ass up trim: rollover target: newest mtime in kept set"
  echo "ass up trim: session clones (${#all_clones_list[@]}):"
  for clone in "${all_clones_list[@]}"; do
    head=$(git -C "$clone" log -1 --oneline main 2>/dev/null || echo "(no commits)")
    markers=""
    _ass_up_trim_clone_dirty "$clone" && markers="${markers} dirty"
    _ass_up_trim_clone_unlanded "$clone" "$canonical" && markers="${markers} unlanded"
    printf 'ass up trim:   %s\n' "$clone"
    printf 'ass up trim:     HEAD %s  behind canonical: %s commit(s)%s\n' \
      "$head" "$(_ass_clone_behind_canonical "$clone" "$canonical")" "$markers"
  done
  echo "ass up trim: plan (keep-latest=${keep_latest}):"
  for clone in "${all_clones_list[@]}"; do
    if _ass_up_trim_clone_unlanded "$clone" "$canonical"; then
      printf 'ass up trim:   keep (unlanded): %s\n' "$clone"
      continue
    fi
    if _ass_up_trim_kept_contains "$clone" "${kept[@]}"; then
      reason="keep-latest (mtime)"
      [[ "$clone" == "$rollover_target" ]] && reason="rollover target (newest mtime)"
      [[ -n "$invoked_from" && "$clone" == "$invoked_from" ]] && reason="current (pwd)"
      printf 'ass up trim:   keep (%s): %s\n' "$reason" "$clone"
      continue
    fi
    if detail=$(_ass_clone_active_agent_session_detail "$clone"); then
      printf 'ass up trim:   keep (active agent session): %s\n' "$clone"
      while IFS= read -r line; do
        [[ -n "$line" ]] && printf 'ass up trim:     %s\n' "$line"
      done <<<"$detail"
      continue
    fi
    harness=$(_ass_up_trim_harness "$clone")
    shortsha=$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || echo unknown)
    datestamp=$(date +%Y%m%d)
    base=$(basename "$clone")
    tarball_dest="${archive_dir}/${harness}-${base}-${shortsha}-${datestamp}.tar.gz"
    if [[ "$dry_run" == 1 ]]; then
      printf 'ass up trim:   prune (dry-run): %s -> %s\n' "$clone" "$tarball_dest"
    else
      printf 'ass up trim:   prune: %s -> %s\n' "$clone" "$tarball_dest"
    fi
  done
  printf 'ass up trim:   rollover target: %s\n' "$rollover_target"

  if [[ "$dry_run" == 1 ]]; then
    echo "ass up trim: dry-run -- not consolidated or pruned (re-run without --dry-run to confirm)"
  elif [[ "$yes" != 1 ]]; then
    read -r -p "ass up trim: consolidate and prune ${#to_archive[@]} session clone(s) for ${name}? [y/N] " line
    [[ "$line" == [yY] || "$line" == [yY][eE][sS] ]] || {
      echo "ass up trim: aborted (not consolidated or pruned)"
      return 1
    }
  fi

  for clone in "${to_archive[@]}"; do
    dirty=0
    unlanded=0
    _ass_up_trim_clone_dirty "$clone" && dirty=1
    _ass_up_trim_clone_unlanded "$clone" "$canonical" && unlanded=1

    if [[ "$unlanded" == 1 ]]; then
      subjects=$(git -C "$clone" log --oneline origin/main..HEAD 2>/dev/null | head -5)
      echo "ass up trim:   kept (unlanded): ${clone}"
      [[ -n "$subjects" ]] && echo "ass up trim:     ${subjects}"
      kept_unlanded=$((kept_unlanded + 1))
      continue
    fi

    if detail=$(_ass_clone_active_agent_session_detail "$clone"); then
      echo "ass up trim:   kept (active agent session): ${clone}"
      while IFS= read -r line; do
        [[ -n "$line" ]] && echo "ass up trim:     ${line}"
      done <<<"$detail"
      continue
    fi

    if [[ "$dirty" == 1 ]]; then
      if [[ "$no_rollover" == 1 ]]; then
        echo "ass up trim:   kept (dirty, --no-rollover): ${clone}"
        kept_dirty=$((kept_dirty + 1))
        continue
      fi
      if [[ "$dry_run" == 1 ]]; then
        echo "ass up trim:   [dry-run] would roll over dirty: ${clone} -> ${rollover_target}"
      else
        read -r files conflicts < <(_ass_up_trim_rollover "$clone" "$rollover_target")
        if [[ "$conflicts" == 1 ]]; then
          echo "ass up trim:   rolled over: ${clone} (${files} file(s); conflicts left for agent)"
        else
          echo "ass up trim:   rolled over: ${clone} (${files} file(s))"
        fi
        rolled=$((rolled + 1))
      fi
    fi

    if _ass_up_trim_archive_clone "$clone" "$archive_dir" "$dry_run"; then
      archived=$((archived + 1))
    else
      return 1
    fi
  done

  if [[ -n "$invoked_from" ]] && _ass_up_trim_kept_contains "$invoked_from" "${kept[@]}"; then
    kept_current=1
  fi

  if [[ "$dry_run" == 1 ]]; then
    echo "ass up trim: ${name} -- dry-run: ${archived} would archive, ${rolled} would roll over -> $(basename "${rollover_target:-none}"), ${kept_unlanded} kept (unlanded), ${kept_dirty} kept (dirty), ${kept_current} kept (current)"
  else
    echo "ass up trim: ${name} -- ${archived} archived, ${rolled} rolled over -> $(basename "${rollover_target:-none}"), ${kept_unlanded} kept (unlanded), ${kept_dirty} kept (dirty), ${kept_current} kept (current)"
    echo "ass up trim: done -- archives in ${archive_dir}"
  fi
  return 0
}

ass_up_trim() {
  local repo="" all=0 dry_run=0 yes=0 no_rollover=0 keep_latest=1 archive_dir=""
  local name host failed=0 ok=0

  if _ass_help_requested "${1:-}"; then
    ass_help_up_trim
    return 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --all) all=1 ;;
      --dry-run) dry_run=1 ;;
      --yes) yes=1 ;;
      --no-rollover) no_rollover=1 ;;
      --keep-latest)
        shift
        keep_latest="${1:-}"
        [[ "$keep_latest" =~ ^[0-9]+$ ]] || {
          echo "ass up trim: --keep-latest requires a number" >&2
          return 1
        }
        ;;
      --archive-dir)
        shift
        archive_dir="${1:-}"
        [[ -n "$archive_dir" ]] || {
          echo "ass up trim: --archive-dir requires a path" >&2
          return 1
        }
        ;;
      -*)
        echo "ass up trim: unknown option: $1 (try: ass up trim help)" >&2
        return 1
        ;;
      *)
        if [[ -n "$repo" ]]; then
          echo "ass up trim: unexpected argument: $1" >&2
          return 1
        fi
        repo="$1"
        ;;
    esac
    shift
  done

  if [[ "$all" == 1 ]]; then
    while IFS= read -r host; do
      [[ -n "$host" ]] || continue
      name=$(basename "$host")
      if _ass_up_trim_one "$name" "$dry_run" "$yes" "$no_rollover" "$keep_latest" "$archive_dir"; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_ass_up_all_consumer_roots | sort -u)
    echo "ass up trim: done -- ${ok} ok, ${failed} failed"
    [[ "$failed" -eq 0 ]]
    return $?
  fi

  if [[ -z "$repo" ]]; then
    repo=$(_ass_resolve_sync_target "" 2>/dev/null | xargs basename 2>/dev/null) || {
      echo "ass up trim: not in a git repo (try: ass up trim <name>)" >&2
      return 1
    }
  fi

  _ass_up_trim_one "$repo" "$dry_run" "$yes" "$no_rollover" "$keep_latest" "$archive_dir"
}

# Run only from agentstartstack canonical local repo; nutup template, refresh consumers.
_ass_up_all_assert_here() {
  local here sync_root

  here=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "ass_up_all: not in a git repo" >&2
    return 1
  }
  here=$(readlink -f "$here")

  sync_root=$(_ass_sync_root agentstartstack) || {
    echo "ass_up_all: agentstartstack canonical local repo not found" >&2
    return 1
  }

  if [[ "$here" != "$sync_root" ]]; then
    echo "ass_up_all: run only from agentstartstack canonical local repo: ${sync_root}" >&2
    return 1
  fi
}

_ass_up_all_consumer_roots() {
  local roots="${AGENTSTARTSTACK_PROJECT_ROOTS:-}"
  local search_root candidate gitmodules
  local IFS=:

  [[ -n "$roots" ]] || return 0
  for search_root in $roots; do
    [[ -n "$search_root" ]] || continue
    [[ -d "$search_root" ]] || continue
    for candidate in "$search_root"/*/; do
      candidate=$(readlink -f "${candidate%/}")
      [[ -d "${candidate}/.git" ]] || continue
      [[ "$(basename "$candidate")" == "agentstartstack" ]] && continue
      gitmodules="${candidate}/.gitmodules"
      [[ -f "$gitmodules" ]] || continue
      if grep -q 'farscapian/agentstartstack' "$gitmodules" 2>/dev/null; then
        printf '%s\n' "$candidate"
      fi
    done
  done
}

# Echo busy session clones for a consumer, one per line: "<clone><TAB><reason>".
# Busy = uncommitted changes, or commits ahead of local-sync/main (agent work in
# flight). ass_up_all defers a consumer's auto-bump while any of its clones is
# busy, so committing + pushing the bump cannot diverge the clone (its next ass
# would otherwise be a non-fast-forward and clobber the agent mid-work).

# Echo in-flight session clones for a consumer, one per line: "<clone><TAB><reason>".
# In-flight = uncommitted changes, or commits ahead of local-sync/main. An
# in-flight clone would turn into a non-fast-forward on its next ass if canonical
# advanced, so ass_up_all does not auto-commit a consumer's bump while any of its
# clones is in-flight -- it drops a watch file instead (see _ass_up_all_flag_clone).
_ass_up_all_busy_sessions() {
  local name="$1" clone status_out ahead reason

  while IFS= read -r clone; do
    [[ -n "$clone" ]] || continue

    status_out=$(git -C "$clone" status --porcelain 2>/dev/null)

    ahead=0
    if git -C "$clone" remote get-url local-sync >/dev/null 2>&1; then
      git -C "$clone" fetch -q local-sync main 2>/dev/null
      ahead=$(git -C "$clone" rev-list --count local-sync/main..HEAD 2>/dev/null || echo 0)
    fi

    reason=""
    [[ -n "$status_out" ]] && reason="uncommitted changes"
    if [[ "$ahead" -gt 0 ]]; then
      [[ -n "$reason" ]] && reason="${reason}, "
      reason="${reason}${ahead} commit(s) ahead of canonical"
    fi

    [[ -n "$reason" ]] && printf '%s\t%s\n' "$clone" "$reason"
  done < <(_ass_session_clones_for_consumer "$name")
}

# Drop a gitignored watch file in a session clone telling its agent to pull the
# pending .agentstartstack bump into the clone before its next commit. The file
# lives at the clone root and is excluded via .git/info/exclude, so it never
# shows in git status, is never committed, and survives reset --hard + clean -fd.
_ass_up_all_flag_clone() {
  local clone="$1" sha="$2"
  local exclude="${clone}/.git/info/exclude"
  local flag="${clone}/.agentstartstack-bump"

  mkdir -p "${clone}/.git/info"
  grep -qxF '/.agentstartstack-bump' "$exclude" 2>/dev/null \
    || printf '/.agentstartstack-bump\n' >> "$exclude"

  cat > "$flag" <<EOF
agentstartstack bump pending -> ${sha}

Do NOT just bump the pointer. Read the producer commits you are adopting and
reconcile this consumer's own copy (wrappers, hooks, docs, config) with them,
then commit and remove this file. Full procedure:
  docs/workflow.md -> "The .agentstartstack-bump watch file"

Quick start:
  git submodule update --init --recursive --remote .agentstartstack
  git add .agentstartstack && rm .agentstartstack-bump

Written by ass_up_all at $(date -Is).
EOF
}

ass_up_all()
{
  if _ass_help_requested "${1:-}"; then
    ass_help_up_all
    return 0
  fi

  if [[ -n "${1:-}" ]]; then
    echo "ass_up_all: takes no arguments (try: ass up --all help)" >&2
    return 1
  fi

  _ass_up_all_assert_here || return 1

  ass_up || return 1

  # Authoritative bump target = agentstartstack canonical HEAD (just pushed by
  # nutup). The in-flight branch must advertise this, not the consumer's stale
  # (and possibly dirty) submodule working-tree HEAD.
  local as_sha
  as_sha=$(git rev-parse --short HEAD) || return 1

  local host name busy iclone ireason sub_sha clone n_flag old_sha new_sha
  local bumped=0 flagged=0 current=0 failed=0 needs_agent=0
  while IFS= read -r host; do
    [[ -n "$host" ]] || continue
    name=$(basename "$host")

    busy=$(_ass_up_all_busy_sessions "$name")
    if [[ -n "$busy" ]]; then
      sub_sha="$as_sha"
      n_flag=0
      while IFS= read -r clone; do
        [[ -n "$clone" ]] || continue
        _ass_up_all_flag_clone "$clone" "$sub_sha"
        n_flag=$((n_flag + 1))
      done < <(_ass_session_clones_for_consumer "$name")
      echo "ass_up_all: ${name} -- in-flight session(s); flagged ${n_flag} clone(s) for bump -> ${sub_sha}, rides along on next agent commit/nut" >&2
      while IFS=$'\t' read -r iclone ireason; do
        [[ -n "$iclone" ]] && echo "ass_up_all:   in-flight: ${iclone} (${ireason})" >&2
      done <<< "$busy"
      flagged=$((flagged + 1))
    else
      old_sha=$(git -C "${host}/.agentstartstack" rev-parse HEAD 2>/dev/null)
      echo "ass_up_all: ${name} -- submodule update --remote .agentstartstack"
      if ! git -C "$host" submodule update --init --recursive --remote .agentstartstack; then
        echo "ass_up_all:   ERROR updating submodule in ${name}" >&2
        failed=$((failed + 1))
      elif [[ -z "$(git -C "$host" status --porcelain -- .agentstartstack 2>/dev/null)" ]]; then
        echo "ass_up_all:   ${name} already current"
        current=$((current + 1))
      else
        new_sha=$(git -C "${host}/.agentstartstack" rev-parse HEAD 2>/dev/null)

        # Action-aware (see workflow.md): a blind pointer bump must NOT skip the
        # CONSUMER-ACTION clauses in the delta. If any producer commit in old..new
        # carries one, do NOT auto-commit -- restore the submodule to its committed
        # SHA and defer to an agent session, which reads the delta and reconciles.
        # Only an action-free delta is safe to auto-commit here.
        if git -C "${host}/.agentstartstack" log --format='%B' "${old_sha}..${new_sha}" 2>/dev/null \
             | grep -q '^[[:space:]]*CONSUMER-ACTION:'; then
          git -C "$host" submodule update --init --recursive .agentstartstack >/dev/null 2>&1
          echo "ass_up_all:   ${name} -- delta ${old_sha:0:7}..${new_sha:0:7} carries CONSUMER-ACTION(s); NOT auto-bumped." >&2
          echo "ass_up_all:     start an agent session for ${name} so it reads the delta and reconciles." >&2
          needs_agent=$((needs_agent + 1))
        else
          sub_sha=$(git -C "${host}/.agentstartstack" rev-parse --short HEAD 2>/dev/null)
          echo "ass_up_all:   committing bump to ${sub_sha} in ${name} (action-free delta)"
          if ! git -C "$host" commit -m "Bump .agentstartstack to ${sub_sha}" -- .agentstartstack; then
            echo "ass_up_all:   ERROR committing bump in ${name}" >&2
            failed=$((failed + 1))
          elif ! git -C "$host" push origin main; then
            echo "ass_up_all:   WARN committed bump but origin push failed in ${name}" >&2
            failed=$((failed + 1))
          else
            bumped=$((bumped + 1))
          fi
        fi
      fi
    fi

    if _ass_up_trim_autotrim_enabled "$host"; then
      if ass_up_trim "$name" --yes; then
        echo "ass_up_all: ${name} -- consolidated and pruned" >&2
      else
        echo "ass_up_all: ${name} -- trim failed (logged; continuing)" >&2
        failed=$((failed + 1))
      fi
    else
      echo "ass_up_all: ${name} -- autotrim disabled (ASS_UP_ALL_AUTOTRIM=0)" >&2
    fi
  done < <(_ass_up_all_consumer_roots | sort -u)

  echo "ass_up_all: done -- ${bumped} bumped, ${current} already current, ${flagged} flagged (in-flight), ${needs_agent} need agent (actions), ${failed} failed"
  [[ "$failed" -eq 0 ]]
}
