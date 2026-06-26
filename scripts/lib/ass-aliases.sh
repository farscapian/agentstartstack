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

# Colon-separated parent dirs under which agent session clones live (Claude, Grok).
# nut discovers clones within these by git origin URL -- no directory-naming scheme
# is assumed. Override by exporting AGENT_SESSION_CLONE_PARENT before sourcing.
: "${AGENT_SESSION_CLONE_PARENT:=${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"
export AGENT_SESSION_CLONE_PARENT

# Shared CLI logging (docs/cli.md, conventions.md -- Script output).
_ASS_ALIASES_LIB_DIR=$(
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
)
# shellcheck source=cli-log.sh
source "${_ASS_ALIASES_LIB_DIR}/cli-log.sh"
: "${AGENTSTARTSTACK_CLI_LOG_PREFIX:=ass}"
: "${AGENTSTARTSTACK_CLI_LOG_DIR:=${HOME}/.docs/logs}"

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
  parents="${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"
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

# Echo absolute paths of session clones whose origin URL == $1, one per line.
# Searches the dirs in AGENT_SESSION_CLONE_PARENT without assuming any naming
# scheme -- clones are identified by git origin URL, so this works regardless of
# how the harness names the worktree dir.
_agentstartstack_clones_for_origin() {
  local want="$1" parents base candidate got
  [[ -n "$want" ]] || return 0
  parents="${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"
  local IFS=:
  for base in $parents; do
    [[ -n "$base" ]] || continue
    [[ -d "$base" ]] || continue
    for candidate in "$base"/*/ "$base"/*/*/; do
      [[ -d "${candidate}.git" ]] || continue
      candidate=$(readlink -f "${candidate%/}")
      got=$(git -C "$candidate" remote get-url origin 2>/dev/null) || continue
      [[ "$got" == "$want" ]] && printf '%s\n' "$candidate"
    done
  done
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

# Unix time when init_*_session.sh last aligned this clone (or .git mtime fallback).
_ass_session_init_time() {
  local clone="$1" marker="${clone}/.git/agentstartstack-session-init"

  if [[ -f "$marker" ]]; then
    tr -d '[:space:]' < "$marker"
    return 0
  fi

  stat -c %Y "${clone}/.git" 2>/dev/null || echo 0
}

# Parse ass / ass up args: optional -f/--force, -h/--help. Pwd-oriented (no repo name).
# Sets _ASS_PARSE_FORCE (0|1).
_ass_parse_args() {
  _ASS_PARSE_FORCE=0
  _ASS_PARSE_HELP=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force)
        _ASS_PARSE_FORCE=1
        ;;
      -h|--help)
        _ASS_PARSE_HELP=1
        return 0
        ;;
      -*)
        echo "ass: unknown option: $1 (try: ass --help)" >&2
        return 1
        ;;
      *)
        _ass_err "ass: unexpected argument: $1 (pwd-oriented -- cd to the repo first)"
        return 1
        ;;
    esac
    shift
  done

  return 0
}

# Echo how many commits on canonical main are not in the clone's main.
# Computed from the canonical repo so the count works even when the clone lacks
# canonical's newer objects locally.
_ass_clone_behind_canonical() {
  local clone="$1" canonical="$2" clone_head can_head
  clone_head=$(git -C "$clone" rev-parse main 2>/dev/null) || {
    printf '?'
    return 0
  }
  can_head=$(git -C "$canonical" rev-parse main 2>/dev/null) || {
    printf '?'
    return 0
  }
  git -C "$canonical" rev-list --count "${clone_head}..${can_head}" 2>/dev/null || printf '?'
}

_ass_print_handoff_report() {
  local sync_target="$1" origin_target="$2" repo_name="$3" selected="${4:-}"
  local pwd_here clone head behind sel
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
  done < <(_agentstartstack_clones_for_origin "$origin_target")

  echo "ass: session clones (${#clones[@]}):"
  if [[ "${#clones[@]}" -eq 0 ]]; then
    echo "ass:   (none)"
    return 0
  fi

  for clone in "${clones[@]}"; do
    head=$(git -C "$clone" log -1 --oneline main 2>/dev/null \
      || git -C "$clone" log -1 --oneline 2>/dev/null \
      || echo "(no commits)")
    behind=$(_ass_clone_behind_canonical "$clone" "$sync_target")
    sel=""
    [[ -n "$selected" && "$clone" == "$(readlink -f "$selected")" ]] \
      && sel="  [selected for handoff]"
    printf 'ass:   %s%s\n' "$clone" "$sel"
    printf 'ass:     HEAD %s  behind canonical: %s commit(s)\n' "$head" "$behind"
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

_ass_canonical_normalize_stash_ref() {
  local token="$1"
  if [[ "$token" =~ ^stash@[{][0-9]+[}]$ ]]; then
    printf '%s\n' "$token"
    return 0
  fi
  if [[ "$token" =~ ^[0-9]+$ ]]; then
    printf 'stash@{%s}\n' "$token"
    return 0
  fi
  return 1
}

_ass_clone_agent_kind() {
  local clone="$1" marker kind
  clone=$(readlink -f "$clone")
  marker="${clone}/.git/agentstartstack-session-agent"
  if [[ -f "$marker" ]]; then
    kind=$(tr -d '[:space:]' < "$marker")
    [[ "$kind" == grok || "$kind" == claude ]] && { printf '%s\n' "$kind"; return 0; }
  fi
  _ass_up_trim_harness "$clone"
}

_ass_canonical_stash_agent_compat_ok() {
  local canonical="$1" clone="$2" stash_ref="$3"
  local script="${_ASS_ALIASES_LIB_DIR}/../ass-stash-compat-check.sh"
  local reason line confirm
  [[ -x "$script" ]] || script="${_ASS_ALIASES_LIB_DIR}/../ass-stash-compat-check.sh"
  [[ -f "$script" ]] || {
    _ass_warn "ass: stash compat check script missing -- skipping agent review"
    return 0
  }
  if bash "$script" --clone "$clone" --canonical "$canonical" --stash-ref "$stash_ref"; then
    return 0
  fi
  reason=$(bash "$script" --clone "$clone" --canonical "$canonical" --stash-ref "$stash_ref" 2>&1 || true)
  _ass_warn "ass: session-clone agent advises NO for ${stash_ref}:"
  printf '%s\n' "$reason" | while IFS= read -r line; do _ass_warn "ass:   ${line}"; done
  read -r -p "ass: move ${stash_ref} anyway? [y/N] " confirm </dev/tty
  [[ "${confirm,,}" == y || "${confirm,,}" == yes ]]
}

_ass_canonical_move_selected_stashes_to_clone() {
  local canonical="$1" clone="$2"
  local selection token ref line moved=0 idx confirm
  local -a refs=() indices=()
  if ! git -C "$canonical" stash list 2>/dev/null | grep -q .; then
    return 0
  fi
  _ass_info "ass: canonical git stashes:"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    _ass_info "ass:   ${line}"
  done < <(git -C "$canonical" stash list 2>/dev/null)
  read -r -p "ass: stashes to move (comma/space-separated, e.g. 0 2 or stash@{0}; empty=none): " selection </dev/tty
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
        _ass_err "ass: invalid stash token: ${token} (use 0, 1, stash@{0}, or all)"
        return 1
      }
      git -C "$canonical" stash show "$ref" >/dev/null 2>&1 || {
        _ass_err "ass: no such stash: ${ref}"
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
    line=$(git -C "$canonical" stash list 2>/dev/null | grep -F "${ref}:" | head -1)
    _ass_info "ass: reviewing canonical stash with session-clone agent: ${line:-${ref}}"
    if ! _ass_canonical_stash_agent_compat_ok "$canonical" "$clone" "$ref"; then
      _ass_info "ass: skipped ${ref}"
      continue
    fi
    _ass_info "ass: moving canonical stash to session clone: ${line:-${ref}}"
    if _ass_canonical_apply_stash_entry_to_clone "$canonical" "$clone" "$ref"; then
      moved=$((moved + 1))
    else
      _ass_err "ass: failed to apply ${ref} to session clone"
      return 1
    fi
  done < <(printf '%s\n' "${indices[@]}" | sort -rn | uniq)
  [[ "$moved" -gt 0 ]] && _ass_ok "ass: moved ${moved} canonical stash(es) to session clone"
  return 0
}

_ass_canonical_move_wip_to_clone() {
  local canonical="$1" clone="$2"
  local confirm has_dirty=0 has_stash=0
  _ass_clone_has_dirty_worktree "$canonical" && has_dirty=1
  git -C "$canonical" stash list 2>/dev/null | grep -q . && has_stash=1
  [[ "$has_dirty" == 1 || "$has_stash" == 1 ]] || return 0
  if [[ "${AS_CLI_QUIET:-0}" -eq 1 ]]; then
    _ass_warn "ass: quiet mode -- not moving canonical WIP to session clone"
    return 0
  fi
  if [[ "$has_dirty" == 1 ]]; then
    _ass_warn "ass: canonical has uncommitted changes"
    read -r -p "ass: stash uncommitted canonical work? [y/N] " confirm </dev/tty
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
  local clone="$1" canonical="$2" clone_head can_head
  clone_head=$(git -C "$clone" rev-parse main 2>/dev/null) || { printf '?'; return 0; }
  can_head=$(git -C "$canonical" rev-parse main 2>/dev/null) || { printf '?'; return 0; }
  git -C "$canonical" rev-list --count "${can_head}..${clone_head}" 2>/dev/null || printf '?'
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
  local force="${2:-0}"
  local origin_target best_dir="" best_time=0 candidate t commit repo_name
  local nut_last=0 init_time skipped=0

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

  if [[ -f "${sync_target}/.git/agentstartstack-ass-last" ]]; then
    nut_last=$(tr -d '[:space:]' < "${sync_target}/.git/agentstartstack-ass-last")
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

    t=$(git -C "$candidate" log -1 --format=%ct 2>/dev/null) || continue
    if [[ "$t" -gt "$best_time" ]]; then
      best_time=$t
      best_dir=$candidate
    fi
  done < <(_agentstartstack_clones_for_origin "$origin_target")

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

  _ass_canonical_move_wip_to_clone "$sync_target" "$best_dir" || return 1
  _ass_handoff_preflight "$best_dir" "$sync_target" || return 1

  _ass_print_handoff_report "$sync_target" "$origin_target" "$repo_name" "$best_dir"

  if git -C "$best_dir" remote get-url local-sync >/dev/null 2>&1; then
    git -C "$best_dir" remote set-url local-sync "$sync_target"
  else
    git -C "$best_dir" remote add local-sync "$sync_target"
  fi

  commit=$(git -C "$best_dir" log -1 --oneline)
  echo "ass: ${commit}"
  echo "ass: ${best_dir} -> ${sync_target}"
  git -C "$best_dir" push local-sync main

  date +%s > "${sync_target}/.git/agentstartstack-ass-last"
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
    for base in ${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}; do
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
  _as_cli_parse_global_flags _ass_argv "$@" || return 1
  _ass_parse_args "${_ass_argv[@]}" "$@" || return 1

  if [[ "$_ASS_PARSE_HELP" == 1 ]]; then
    cat <<'EOF'
ass -- AgentStartStack handoff (local-sync)

Perform local-sync with the canonical local repo (session clone -> local-sync remote).
Prints pwd, canonical repo, every session clone, and how far behind canonical each is.

  ass                 pwd-oriented handoff (cd to canonical or session clone)
  ass -f              only session clones initialized after the last ass
  ass up              local-sync, then git push origin main
  ass up -f           as ass -f, then push
  ass up trim         consolidate and prune stale session clones
  ass up --all        ass up agentstartstack, refresh consumer submodules
  ass dropit <src>    copy generic work into agentstartstack session clone

Repo roots:  $AGENTSTARTSTACK_PROJECT_ROOTS (colon-separated dirs holding <name>/)
Session:     clones under ~/.claude/worktrees/ and ~/.grok/worktrees/
             (matched to a canonical repo by git origin URL, any dir name)

-f, --force  Ignore session clones initialized before the last ass; among the
             remaining clones, pick the one with the newest commit on main.
             Use after starting a fresh session (init_*_session.sh) so an older
             stale clone cannot win.
EOF
    return 0
  fi

  local sync_target
  sync_target=$(_ass_resolve_sync_target "") || return 1
  _ass_push "$sync_target" "$_ASS_PARSE_FORCE"
}

ass_up()
{
  local -a _ass_argv
  _as_cli_parse_global_flags _ass_argv "$@" || return 1
  set -- "${_ass_argv[@]}"
  if [[ "${1:-}" == "trim" ]]; then
    shift
    ass_up_trim "$@"
    return $?
  fi

  _ass_parse_args "$@" || return 1

  if [[ "$_ASS_PARSE_HELP" == 1 ]]; then
    cat <<'EOF'
ass up -- local-sync with canonical local repo, then git push origin main

  ass up              pwd-oriented (cd to canonical or session clone)
  ass up -f           only session clones initialized after the last ass, then push
  ass up trim          consolidate and prune stale session clones (see: ass up trim --help)

-f, --force  See ass --help. Prefer this when handing off from a session started
             after the previous ass so older session clones are not selected.
EOF
    return 0
  fi

  local sync_target
  sync_target=$(_ass_resolve_sync_target "") || return 1
  _ass_push "$sync_target" "$_ASS_PARSE_FORCE" || return 1
  _ass_info "ass up: ${sync_target} -> origin main"
  git -C "$sync_target" push origin main
}

# dropit -- from a CONSUMER session clone, stash a generic feature/doc that
# belongs upstream in agentstartstack into agentstartstack's latest session clone
# (so it can be committed there and flow upstream) instead of forking it into the
# consumer. Runs ONLY from a consumer session clone. Copy-only: it never edits the
# consumer or the agentstartstack clone's history -- you review and commit there.
#   dropit <src> [<dest>]
dropit() {
  local src="${1:-}" dest="${2:-}"

  if [[ -z "$src" || "$src" == "-h" || "$src" == "--help" ]]; then
    cat <<'EOF'
dropit -- stash a generic feature/doc into agentstartstack's latest session clone

Run from a CONSUMER session clone. Copies something that belongs upstream in
agentstartstack into that repo's newest session clone -- do not fork it here.

  dropit <src> [<dest>]
    <src>   file/dir in this clone that belongs in agentstartstack
    <dest>  path relative to the agentstartstack clone root
            (default: same relative path as <src> here)

Then review + commit in the agentstartstack clone and hand off with ass. If <src>
was a fork created here, delete it from this consumer afterward.
EOF
    return 0
  fi

  local here
  here=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "dropit: not in a git repo" >&2
    return 1
  }
  here=$(readlink -f "$here")

  # Guard: must be inside an agent session clone (under a clone parent).
  local base in_clone=0
  local IFS=:
  for base in ${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}; do
    [[ -n "$base" ]] || continue
    [[ "$here" == "$base"/* ]] && { in_clone=1; break; }
  done
  unset IFS
  if [[ "$in_clone" != 1 ]]; then
    echo "dropit: run only from an agent session clone (under AGENT_SESSION_CLONE_PARENT)" >&2
    return 1
  fi

  # Guard: must be a CONSUMER (has the .agentstartstack submodule), not
  # agentstartstack itself. The submodule's origin is the agentstartstack origin.
  local as_origin
  as_origin=$(git -C "${here}/.agentstartstack" remote get-url origin 2>/dev/null) || {
    echo "dropit: no .agentstartstack submodule here -- not a consumer clone" >&2
    return 1
  }

  # Resolve <src> and its path relative to this clone root.
  local abs_src rel
  abs_src=$(readlink -f "$src" 2>/dev/null) || { echo "dropit: not found: $src" >&2; return 1; }
  [[ -e "$abs_src" ]] || { echo "dropit: not found: $src" >&2; return 1; }
  case "$abs_src" in
    "$here"/*) rel="${abs_src#"${here}/"}" ;;
    *) echo "dropit: <src> must be inside this clone: $abs_src" >&2; return 1 ;;
  esac
  [[ -n "$dest" ]] || dest="$rel"

  # Find the latest agentstartstack session clone by origin URL (newest commit).
  local best="" best_t=0 cand t
  while IFS= read -r cand; do
    [[ -n "$cand" ]] || continue
    [[ "$cand" == "$here" ]] && continue
    t=$(git -C "$cand" log -1 --format=%ct 2>/dev/null) || continue
    if [[ "$t" -gt "$best_t" ]]; then
      best_t=$t
      best="$cand"
    fi
  done < <(_agentstartstack_clones_for_origin "$as_origin")

  if [[ -z "$best" ]]; then
    echo "dropit: no agentstartstack session clone found (origin: $as_origin)" >&2
    echo "dropit:   create one (clone agentstartstack into AGENT_SESSION_CLONE_PARENT) and retry" >&2
    return 1
  fi

  local target="${best}/${dest}"
  mkdir -p "$(dirname "$target")"
  cp -r "$abs_src" "$target"

  # Stamp Dropit-Id and update the consumer ledger for traceable round-trips.
  local session_guid desc ledger="${here}/.agentstartstack-dropits"
  session_guid=$(basename "$here")
  desc="$(basename "$src")"

  if [[ -f "$target" ]]; then
    if ! grep -q '^Dropit-Id:' "$target" 2>/dev/null; then
      { printf 'Dropit-Id: %s\n\n' "$session_guid"; cat "$target"; } > "${target}.dropit-tmp"
      mv "${target}.dropit-tmp" "$target"
    fi
  else
    echo "dropit: note -- multi-file drop; ensure each file carries Dropit-Id: ${session_guid}" >&2
  fi

  if [[ -f "$ledger" ]] && grep -qF "$session_guid" "$ledger" 2>/dev/null; then
    echo "dropit: ledger already lists ${session_guid} in ${ledger}" >&2
  else
    printf '%s  %s\n' "$session_guid" "$desc" >> "$ledger"
    echo "dropit: recorded ${session_guid} in ${ledger} (commit this file in the consumer)" >&2
  fi

  echo "dropit: ${rel}  ->  ${best}/${dest}"
  echo "dropit: review + commit in the agentstartstack clone, then ass."
}


# ass prune -- consolidate one session clone into the newest, then prune it.

_ass_prune_resolve_target() {
  local arg="${1:-}" here
  if [[ -n "$arg" ]]; then
    [[ -d "$arg" ]] || { _ass_err "ass prune: not found: $arg"; return 1; }
    readlink -f "$arg"
    return 0
  fi
  here=$(git rev-parse --show-toplevel 2>/dev/null) || {
    _ass_err "ass prune: not in a git repo (pass clone path)"
    return 1
  }
  readlink -f "$here"
}

ass_prune() {
  local target="${1:-}" clone canonical name survivor archive_dir
  local -a all=()
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
ass prune -- consolidate one session clone into the newest, then remove it

  ass prune                 pwd must be a session clone
  ass prune <clone-path>    explicit clone to prune

Refuses unlanded clones (commits not in origin/main). Dirty work is rolled into
the survivor (newest commit on main, same rule as ass handoff).
EOF
    return 0
  fi
  clone=$(_ass_prune_resolve_target "$target") || return 1
  canonical=$(_ass_sync_target_from_worktree "$clone") || {
    _ass_err "ass prune: cannot resolve canonical from: $clone"
    return 1
  }
  canonical=$(readlink -f "$canonical")
  name=$(basename "$canonical")
  if _ass_up_trim_clone_unlanded "$clone" "$canonical"; then
    _ass_err "ass prune: clone has unlanded commits -- cherry-pick or ass handoff first"
    return 1
  fi
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    all+=("$(readlink -f "$c")")
  done < <(_ass_up_all_session_clones "$name")
  mapfile -t all < <(
    for c in "${all[@]}"; do
      printf '%s %s\n' "$(git -C "$c" log -1 --format=%ct main 2>/dev/null || echo 0)" "$c"
    done | sort -rn -k1,1 | awk '{print $2}'
  )
  survivor="${all[0]:-}"
  [[ -n "$survivor" ]] || { _ass_err "ass prune: no session clones for ${name}"; return 1; }
  [[ "$clone" != "$survivor" ]] || { _ass_info "ass prune: clone is already the newest"; return 0; }
  if _ass_up_trim_clone_dirty "$clone"; then
    _ass_info "ass prune: consolidating dirty work: ${clone} -> ${survivor}"
    read -r _f _c < <(_ass_up_trim_rollover "$clone" "$survivor")
  fi
  archive_dir=$(_ass_up_trim_resolve_archive_dir "$canonical" "")
  _ass_up_trim_archive_clone "$clone" "$archive_dir" 0
}

ass_new() {
  local agent="" canonical origin parent session_id clone_path script_dir
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
ass new -- create and align a new session clone (from canonical pwd)

  ass new --grok      Grok / Cursor session clone
  ass new --claude    Claude Code session clone

Run from the canonical local repo. Creates AGENT_SESSION_CLONE_PARENT/<timestamp>/.
EOF
    return 0
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --grok) agent=grok; shift ;;
      --claude) agent=claude; shift ;;
      *) _ass_err "ass new: unknown option: $1"; return 1 ;;
    esac
  done
  [[ -n "$agent" ]] || { _ass_err "ass new: pass --grok or --claude"; return 1; }
  canonical=$(git rev-parse --show-toplevel 2>/dev/null) || {
    _ass_err "ass new: run from the canonical local repo"; return 1
  }
  canonical=$(readlink -f "$canonical")
  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || {
    _ass_err "ass new: canonical has no origin remote"; return 1
  }
  parent="${AGENT_SESSION_CLONE_PARENT%%:*}"
  parent="${parent:-${HOME}/.grok/worktrees}"
  session_id=$(date +%s)
  clone_path="${parent}/$(basename "$canonical")/${session_id}"
  mkdir -p "$(dirname "$clone_path")"
  git clone "$origin" "$clone_path"
  script_dir="${_ASS_ALIASES_LIB_DIR}/.."
  "${script_dir}/init_agent_session.sh" "--${agent}" "$clone_path"
  _ass_ok "ass new: session clone ready: ${clone_path}"
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
  parents="${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"
  clone=$(readlink -f "$clone")
  local IFS=:
  for base in $parents; do
    [[ -n "$base" ]] || continue
    if [[ "$clone" == "$base"/* ]]; then
      case "$base" in
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
  printf '%s\n' "${HOME}/.docs/archives/${name}/agent_clones"
}

_ass_up_trim_rollover() {
  local old="$1" target="$2"
  local patch tmp relpath files=0 conflicts=0

  patch=$(mktemp "${TMPDIR:-/tmp}/nutup-trim-patch.XXXXXX")
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

_ass_up_trim_archive_clone() {
  local clone="$1" archive_dir="$2" dry_run="$3"
  local parent base harness shortsha datestamp dest tarball

  clone=$(readlink -f "$clone")
  parent=$(dirname "$clone")
  base=$(basename "$clone")
  [[ -d "${clone}/.git" ]] || {
    echo "ass up trim:   ERROR ${clone} has no .git directory -- refusing" >&2
    return 1
  }

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
  rm -rf "$clone"
  echo "ass up trim:   pruned ${clone} -> ${tarball}"
  return 0
}

_ass_up_trim_resolve_invoked_from() {
  local canonical="$1" here in_clone=0 base
  here=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  here=$(readlink -f "$here")
  local IFS=:
  for base in ${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}; do
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
  local canonical archive_dir invoked_from rollover_target
  local -a all_clones=() all_clones_list=() kept=() to_archive=()
  local clone mtime t dirty unlanded archived=0 rolled=0 kept_unlanded=0 kept_dirty=0
  local files conflicts subjects line skip k reason pwd_here head markers

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
  done < <(_ass_up_all_session_clones "$name")

  if [[ "${#all_clones_list[@]}" -eq 0 ]]; then
    echo "ass up trim: ${name} -- no session clones found"
    return 0
  fi

  # Survivor = newest commit on main (same rule as nut). Keep the top keep_latest
  # clones by that ordering; consolidate dirty work into the survivor, prune the rest.
  mapfile -t all_clones < <(
    for clone in "${all_clones_list[@]}"; do
      printf '%s %s\n' "$(git -C "$clone" log -1 --format=%ct main 2>/dev/null || echo 0)" "$clone"
    done | sort -rn -k1,1 | awk '{print $2}'
  )

  t=0
  for clone in "${all_clones[@]}"; do
    [[ "$t" -ge "$keep_latest" ]] && break
    kept+=("$clone")
    t=$((t + 1))
  done

  rollover_target="${kept[0]:-}"

  to_archive=()
  for clone in "${all_clones_list[@]}"; do
    _ass_up_trim_kept_contains "$clone" "${kept[@]}" && continue
    to_archive+=("$clone")
  done
  mapfile -t to_archive < <(
    for clone in "${to_archive[@]}"; do
      printf '%s %s\n' "$(git -C "$clone" log -1 --format=%ct main 2>/dev/null || echo 0)" "$clone"
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
  echo "ass up trim: survivor: newest commit on main (same rule as nut)"
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
      reason="newest commit on main (keep-latest)"
      [[ "$clone" == "$rollover_target" ]] && reason="survivor (newest commit on main)"
      printf 'ass up trim:   keep (%s): %s\n' "$reason" "$clone"
      continue
    fi
    if [[ "$dry_run" == 1 ]]; then
      printf 'ass up trim:   prune (dry-run): %s\n' "$clone"
    else
      printf 'ass up trim:   prune: %s\n' "$clone"
    fi
  done
  printf 'ass up trim:   consolidation target: %s\n' "$rollover_target"

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

    if [[ "$dirty" == 1 ]]; then
      if [[ "$no_rollover" == 1 ]]; then
        echo "ass up trim:   kept (dirty, --no-rollover): ${clone}"
        kept_dirty=$((kept_dirty + 1))
        continue
      fi
      if [[ "$dry_run" == 1 ]]; then
        echo "ass up trim:   [dry-run] would consolidate dirty: ${clone} -> ${rollover_target}"
      else
        read -r files conflicts < <(_ass_up_trim_rollover "$clone" "$rollover_target")
        if [[ "$conflicts" == 1 ]]; then
          echo "ass up trim:   consolidated: ${clone} (${files} file(s); conflicts left for agent)"
        else
          echo "ass up trim:   consolidated: ${clone} (${files} file(s))"
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

  if [[ "$dry_run" == 1 ]]; then
    echo "ass up trim: ${name} -- dry-run: ${archived} would prune, ${rolled} would consolidate -> ${rollover_target}, ${kept_unlanded} kept (unlanded), ${kept_dirty} kept (dirty)"
  else
    echo "ass up trim: ${name} -- consolidated and pruned: ${rolled} consolidated -> ${rollover_target}, ${archived} pruned, ${kept_unlanded} kept (unlanded), ${kept_dirty} kept (dirty)"
    echo "ass up trim:   prune archives in ${archive_dir}"
  fi
  return 0
}

ass_up_trim() {
  local repo="" all=0 dry_run=0 yes=0 no_rollover=0 keep_latest=1 archive_dir=""
  local name host failed=0 ok=0

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
ass up trim -- consolidate and prune stale agent session clones for a consumer

  ass up trim                 infer consumer from pwd
  ass up trim <project>       named consumer
  ass up trim --all           every configured consumer
  ass up trim --dry-run       print plan only (never consolidates or prunes)
  ass up trim --yes           skip confirmation prompt (still consolidates/prunes)
  ass up trim --no-rollover   keep dirty older clones instead of consolidating
  ass up trim --keep-latest N keep N newest-by-commit clones (default 1)
  ass up trim --archive-dir <path>

Run from the canonical repo (pwd is canonical). Survivor = newest commit on main
(same rule as nut). Consolidates uncommitted work from older clones into the
survivor, then prunes
stale clones (verified .tar.gz archive, then remove source dir). Un-landed clones
(commits not in origin/main) are kept for agent cherry-pick.
EOF
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
        echo "ass up trim: unknown option: $1 (try: ass up trim --help)" >&2
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
# List all session clones for a consumer (one absolute path per line), matched by
# git origin URL so no worktree directory-naming scheme is assumed.
_ass_up_all_session_clones() {
  local name="$1" canonical origin
  canonical=$(_ass_sync_root "$name") || return 0
  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || return 0
  _agentstartstack_clones_for_origin "$origin"
}

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
  done < <(_ass_up_all_session_clones "$name")
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
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
ass up --all -- local-sync and push agentstartstack, refresh .agentstartstack in consumer repos

Run only from the agentstartstack canonical local repo (not a session clone).

For each consumer repo:
  - No in-flight session clone -> if the delta is action-free, auto-commit the
    .agentstartstack bump and push origin main. If the delta carries any
    CONSUMER-ACTION, do NOT auto-commit (would skip the actions); report it under
    "need agent (actions)" and leave it for an agent session to reconcile.
  - In-flight session clone(s) (uncommitted changes or ahead of canonical) ->
    do NOT touch canonical (would non-fast-forward an agent's nut). Instead drop
    a gitignored .agentstartstack-bump watch file in every clone; the bump rides
    along on the agent's next commit and reaches canonical via ass.

  ass up --all
  ass up --all --help
EOF
    return 0
  fi

  if [[ -n "${1:-}" ]]; then
    echo "ass_up_all: takes no arguments (try: ass_up_all --help)" >&2
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
      done < <(_ass_up_all_session_clones "$name")
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
