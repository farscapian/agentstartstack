#!/usr/bin/env bash
# nut-aliases.sh -- canonical nut / nutup / nutupyall shell functions.
#
# Single source of truth for the human-side git-handoff aliases. Installed into
# the human's shell by install-shell-aliases.sh (which both init_*_session.sh
# call); do not execute directly -- it is meant to be sourced. nut.md documents
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
  printf 'nut: AGENTSTARTSTACK_PROJECT_ROOTS must not point under AGENT_SESSION_CLONE_PARENT (%s)\n' \
    "$roots" >&2
  printf 'nut:   export AGENTSTARTSTACK_PROJECT_ROOTS to the dir holding canonical checkouts (e.g. ~/Sync/mini_projects)\n' >&2
  printf 'nut:   then re-run scripts/install-shell-aliases.sh and source ~/.bashrc\n' >&2
  return 1
}

_agentstartstack_guard_project_roots || true

# nut / nutup -- Newest commit Until Transferred
#
# Usage:
#   nut              # local-sync with canonical local repo
#   nut -f           # local-sync from a session clone initialized after last nut
#   nutup            # local-sync, then git push origin main
#   nutup -f         # as nut -f, then push
#   nutup iotstack   # explicit repo + local-sync + push
#   nutupyall        # nutup agentstartstack, refresh consumer submodules
#
# Timestamp markers (machine-local, under .git/):
#   canonical:  .git/agentstartstack-nut-last      (unix time; set after each nut)
#   session:    .git/agentstartstack-session-init  (unix time; set by init_*_session.sh)

# Locate a canonical repo named "$1" under any of AGENTSTARTSTACK_PROJECT_ROOTS
# (colon-separated dirs that hold repo checkouts as <root>/<name>). No location
# is assumed -- if the var is empty, name-based lookup fails (pwd-based nut still
# works). install-shell-aliases.sh seeds a default from the install location.
_nut_sync_root() {
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
_nut_sync_target_from_worktree() {
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
_nut_guard_active_sessions() {
  local sync_target="$1"

  # Match on the repo directory name (basename of the resolved canonical path),
  # so the guard is independent of where the human keeps their checkouts.
  case "${sync_target##*/}" in
    iotstack)
      if pgrep -af '(/iotstack\.sh|/iotstack) ' >/dev/null 2>&1; then
        echo "nut: iotstack is running -- wait for it to finish" >&2
        return 1
      fi
      ;;
    printstack)
      if pgrep -af '(printstack\.sh|/printstack) ' >/dev/null 2>&1; then
        echo "nut: printstack is running -- wait for it to finish" >&2
        return 1
      fi
      ;;
    wrtstack)
      if pgrep -af 'wrtstack (build|flash)' >/dev/null 2>&1; then
        echo "nut: wrtstack is running -- wait for it to finish" >&2
        return 1
      fi
      ;;
  esac

  return 0
}

# Unix time when init_*_session.sh last aligned this clone (or .git mtime fallback).
_nut_session_init_time() {
  local clone="$1" marker="${clone}/.git/agentstartstack-session-init"

  if [[ -f "$marker" ]]; then
    tr -d '[:space:]' < "$marker"
    return 0
  fi

  stat -c %Y "${clone}/.git" 2>/dev/null || echo 0
}

# Parse nut/nutup args: optional -f/--force, optional repo name, -h/--help.
# Sets _NUT_PARSE_FORCE (0|1) and _NUT_PARSE_REPO (name or empty).
_nut_parse_args() {
  _NUT_PARSE_FORCE=0
  _NUT_PARSE_REPO=""
  _NUT_PARSE_HELP=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--force)
        _NUT_PARSE_FORCE=1
        ;;
      -h|--help)
        _NUT_PARSE_HELP=1
        return 0
        ;;
      -*)
        echo "nut: unknown option: $1 (try: nut --help)" >&2
        return 1
        ;;
      *)
        if [[ -n "$_NUT_PARSE_REPO" ]]; then
          echo "nut: unexpected argument: $1 (try: nut --help)" >&2
          return 1
        fi
        _NUT_PARSE_REPO="$1"
        ;;
    esac
    shift
  done

  return 0
}

_nut_push() {
  local sync_target="$1"
  local force="${2:-0}"
  local origin_target best_dir="" best_time=0 candidate t commit repo_name
  local nut_last=0 init_time skipped=0

  sync_target=$(readlink -f "$sync_target")
  [[ -d "${sync_target}/.git" ]] || {
    echo "nut: not a git repo: $sync_target" >&2
    return 1
  }

  _nut_guard_active_sessions "$sync_target" || return 1

  origin_target=$(git -C "$sync_target" remote get-url origin 2>/dev/null) || {
    echo "nut: canonical local repo has no origin remote: $sync_target" >&2
    return 1
  }

  repo_name=$(basename "$sync_target")

  if [[ -f "${sync_target}/.git/agentstartstack-nut-last" ]]; then
    nut_last=$(tr -d '[:space:]' < "${sync_target}/.git/agentstartstack-nut-last")
    [[ "$nut_last" =~ ^[0-9]+$ ]] || nut_last=0
  fi

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue

    if [[ "$force" == 1 && "$nut_last" -gt 0 ]]; then
      init_time=$(_nut_session_init_time "$candidate")
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
      echo "nut: --force: no session clone initialized after the last nut for ${repo_name}" >&2
      echo "nut:   last nut: $(date -d "@${nut_last}" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date -r "$nut_last" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || echo "@${nut_last}")" >&2
      if [[ "$skipped" -gt 0 ]]; then
        echo "nut:   ignored ${skipped} older session clone(s); align a new session (init_*_session.sh) or omit --force" >&2
      fi
    else
      echo "nut: no session clone for ${repo_name}" >&2
    fi
    return 1
  fi

  if [[ "$force" == 1 && "$skipped" -gt 0 ]]; then
    echo "nut: --force: ignored ${skipped} session clone(s) initialized before last nut" >&2
  fi

  if git -C "$best_dir" remote get-url local-sync >/dev/null 2>&1; then
    git -C "$best_dir" remote set-url local-sync "$sync_target"
  else
    git -C "$best_dir" remote add local-sync "$sync_target"
  fi

  commit=$(git -C "$best_dir" log -1 --oneline)
  echo "nut: ${commit}"
  echo "nut: ${best_dir} -> ${sync_target}"
  git -C "$best_dir" push local-sync main

  date +%s > "${sync_target}/.git/agentstartstack-nut-last"
}

_nut_resolve_sync_target() {
  local repo_arg="${1:-}"
  local here sync_target base in_clone

  if [[ -n "$repo_arg" ]]; then
    sync_target=$(_nut_sync_root "$repo_arg") || {
      echo "nut: no canonical local repo found for: ${repo_arg}" >&2
      echo "nut:   set AGENTSTARTSTACK_PROJECT_ROOTS to the dir(s) holding your checkouts" >&2
      return 1
    }
  else
    here=$(git rev-parse --show-toplevel 2>/dev/null) || {
      echo "nut: not in a git repo (try: nut <name>)" >&2
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
      sync_target=$(_nut_sync_target_from_worktree "$here") || {
        echo "nut: cannot resolve canonical local repo from: $here" >&2
        return 1
      }
    else
      sync_target="$here"
    fi
  fi

  printf '%s\n' "$(readlink -f "$sync_target")"
}

nut()
{
  _nut_parse_args "$@" || return 1

  if [[ "$_NUT_PARSE_HELP" == 1 ]]; then
    cat <<'EOF'
nut -- Newest commit Until Transferred

Perform local-sync with the canonical local repo (session clone -> local-sync remote).

  nut                 infer repo from pwd
  nut <name>          e.g. nut printstack, nut iotstack, nut wrtstack
  nut -f              only session clones initialized after the last nut
  nutup               local-sync, then git push origin main
  nutup -f            as nut -f, then push
  nutup <name>        local-sync for <name>, then push
  nutupyall           nutup agentstartstack, refresh .agentstartstack submodules

Repo roots:  $AGENTSTARTSTACK_PROJECT_ROOTS (colon-separated dirs holding <name>/)
Session:     clones under ~/.claude/worktrees/ and ~/.grok/worktrees/
             (matched to a canonical repo by git origin URL, any dir name)

-f, --force  Ignore session clones initialized before the last nut; among the
             remaining clones, pick the one with the newest commit on main.
             Use after starting a fresh session (init_*_session.sh) so an older
             stale clone cannot win.
EOF
    return 0
  fi

  local sync_target
  sync_target=$(_nut_resolve_sync_target "$_NUT_PARSE_REPO") || return 1
  _nut_push "$sync_target" "$_NUT_PARSE_FORCE"
}

nutup()
{
  if [[ "${1:-}" == "trim" ]]; then
    shift
    nutup_trim "$@"
    return $?
  fi

  _nut_parse_args "$@" || return 1

  if [[ "$_NUT_PARSE_HELP" == 1 ]]; then
    cat <<'EOF'
nutup -- local-sync with canonical local repo, then git push origin main

  nutup               infer repo from pwd
  nutup <name>        e.g. nutup printstack, nutup wrtstack
  nutup -f            only session clones initialized after the last nut, then push
  nutup trim          consolidate and prune stale session clones (see: nutup trim --help)

-f, --force  See nut --help. Prefer this when handing off from a session started
             after the previous nut so older session clones are not selected.
EOF
    return 0
  fi

  local sync_target
  sync_target=$(_nut_resolve_sync_target "$_NUT_PARSE_REPO") || return 1
  _nut_push "$sync_target" "$_NUT_PARSE_FORCE" || return 1
  echo "nutup: ${sync_target} -> origin main"
  git -C "$sync_target" push origin main
}

# Alias: nutitup -- same as nutup (args pass through)
alias nutitup='nutup'

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

Then review + commit in the agentstartstack clone and hand off with nut. If <src>
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
  echo "dropit: review + commit in the agentstartstack clone, then nut."
}

# nutup trim -- consolidate and prune stale agent session clones for a consumer.
# See agentstartstack/nut.md and workflow.md.

_nutup_trim_load_env() {
  local canonical="$1" env_file="${canonical}/.agentstartstack.env"
  PROJECT_NAME="$(basename "$canonical")"
  ACTIVE_GUARD_PGREP=""
  AGENTSTARTSTACK_CLONE_ARCHIVE_DIR=""
  NUTUPYALL_AUTOTRIM=1
  [[ -f "$env_file" ]] || return 0
  # shellcheck source=/dev/null
  source "$env_file"
  return 0
}

_nutup_trim_autotrim_enabled() {
  local canonical="$1"
  _nutup_trim_load_env "$canonical"
  [[ "${NUTUPYALL_AUTOTRIM:-1}" != "0" ]]
}

_nutup_trim_guard() {
  local canonical="$1" name="$2"
  _nutup_trim_load_env "$canonical" || return 1
  if [[ -n "${ACTIVE_GUARD_PGREP:-}" ]] \
     && pgrep -af "$ACTIVE_GUARD_PGREP" >/dev/null 2>&1; then
    echo "nutup trim: ${name} CLI active (ACTIVE_GUARD_PGREP) -- skipping" >&2
    return 1
  fi
  _nut_guard_active_sessions "$canonical" || return 1
}

_nutup_trim_clone_mtime() {
  stat -c %Y "$1/.git" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

_nutup_trim_clone_dirty() {
  [[ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]]
}

_nutup_trim_clone_unlanded() {
  local clone="$1" canonical="$2" head
  head=$(git -C "$clone" rev-parse HEAD 2>/dev/null) || return 1
  git -C "$canonical" fetch -q origin 2>/dev/null || true
  ! git -C "$canonical" merge-base --is-ancestor "$head" origin/main 2>/dev/null
}

_nutup_trim_harness() {
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

_nutup_trim_resolve_archive_dir() {
  local canonical="$1" override="$2" name
  _nutup_trim_load_env "$canonical"
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

_nutup_trim_rollover() {
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

_nutup_trim_archive_clone() {
  local clone="$1" archive_dir="$2" dry_run="$3"
  local parent base harness shortsha datestamp dest tarball

  clone=$(readlink -f "$clone")
  parent=$(dirname "$clone")
  base=$(basename "$clone")
  [[ -d "${clone}/.git" ]] || {
    echo "nutup trim:   ERROR ${clone} has no .git directory -- refusing" >&2
    return 1
  }

  harness=$(_nutup_trim_harness "$clone")
  shortsha=$(git -C "$clone" rev-parse --short HEAD 2>/dev/null || echo unknown)
  datestamp=$(date +%Y%m%d)
  dest="${archive_dir}/${harness}-${base}-${shortsha}-${datestamp}.tar.gz"

  if [[ "$dry_run" == 1 ]]; then
    echo "nutup trim:   [dry-run] prune ${clone} -> ${dest}"
    echo "nutup trim:   [dry-run] rm -rf ${clone}"
    return 0
  fi

  mkdir -p "$archive_dir"
  tarball="$dest"
  if ! tar czf "$tarball" -C "$parent" "$base"; then
    echo "nutup trim:   ERROR archiving ${clone}" >&2
    return 1
  fi
  if ! tar tzf "$tarball" >/dev/null 2>&1; then
    echo "nutup trim:   ERROR verifying ${tarball} -- source left in place" >&2
    rm -f "$tarball"
    return 1
  fi
  rm -rf "$clone"
  echo "nutup trim:   pruned ${clone} -> ${tarball}"
  return 0
}

_nutup_trim_resolve_invoked_from() {
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
  if [[ "$(_nut_sync_target_from_worktree "$here" 2>/dev/null || true)" == "$(readlink -f "$canonical")" ]]; then
    printf '%s\n' "$here"
  fi
}

_nutup_trim_kept_contains() {
  local needle="$1" k
  shift
  for k in "$@"; do
    [[ "$k" == "$needle" ]] && return 0
  done
  return 1
}

_nutup_trim_one() {
  local name="$1" dry_run="$2" yes="$3" no_rollover="$4" keep_latest="$5" archive_override="$6"
  local canonical archive_dir invoked_from rollover_target
  local -a all_clones=() all_clones_list=() kept=() kept_dedup=() to_archive=()
  local clone mtime t dirty unlanded archived=0 rolled=0 kept_unlanded=0 kept_dirty=0
  local files conflicts subjects line skip k reason pwd_here head markers

  canonical=$(_nut_sync_root "$name") || {
    echo "nutup trim: no canonical local repo for: ${name}" >&2
    return 1
  }
  canonical=$(readlink -f "$canonical")

  _nutup_trim_guard "$canonical" "$name" || return 1

  archive_dir=$(_nutup_trim_resolve_archive_dir "$canonical" "$archive_override")
  invoked_from=$(_nutup_trim_resolve_invoked_from "$canonical" || true)

  while IFS= read -r clone; do
    [[ -n "$clone" ]] || continue
    all_clones_list+=("$(readlink -f "$clone")")
  done < <(_nutupyall_session_clones "$name")

  if [[ "${#all_clones_list[@]}" -eq 0 ]]; then
    echo "nutup trim: ${name} -- no session clones found"
    return 0
  fi

  # Build kept set: invoked clone + N most-recently-modified clones.
  if [[ -n "$invoked_from" ]]; then
    kept+=("$invoked_from")
  fi

  mapfile -t all_clones < <(
    for clone in "${all_clones_list[@]}"; do
      printf '%s %s\n' "$(_nutup_trim_clone_mtime "$clone")" "$clone"
    done | sort -rn -k1,1 | awk '{print $2}'
  )

  t=0
  for clone in "${all_clones[@]}"; do
    [[ "$t" -ge "$keep_latest" ]] && break
    _nutup_trim_kept_contains "$clone" "${kept[@]}" || kept+=("$clone")
    t=$((t + 1))
  done

  kept_dedup=()
  for clone in "${kept[@]}"; do
    _nutup_trim_kept_contains "$clone" "${kept_dedup[@]}" || kept_dedup+=("$clone")
  done
  kept=("${kept_dedup[@]}")

  # Rollover target = newest clone in kept set.
  rollover_target=$(
    for clone in "${kept[@]}"; do
      printf '%s %s\n' "$(_nutup_trim_clone_mtime "$clone")" "$clone"
    done | sort -rn -k1,1 | head -1 | awk '{print $2}'
  )

  # Classify clones outside the kept set (oldest first for rollover ordering).
  to_archive=()
  for clone in "${all_clones[@]}"; do
    skip=0
    for k in "${kept[@]}"; do
      [[ "$clone" == "$k" ]] && { skip=1; break; }
    done
    [[ "$skip" == 1 ]] && continue
    to_archive+=("$clone")
  done
  mapfile -t to_archive < <(
    for clone in "${to_archive[@]}"; do
      printf '%s %s\n' "$(_nutup_trim_clone_mtime "$clone")" "$clone"
    done | sort -n -k1,1 | awk '{print $2}'
  )

  git -C "$canonical" fetch -q origin 2>/dev/null || true

  pwd_here=$(readlink -f "$(pwd)" 2>/dev/null || pwd)
  echo "nutup trim: pwd: ${pwd_here}"
  echo "nutup trim: canonical (${name}): ${canonical}"
  if [[ -n "$invoked_from" ]]; then
    echo "nutup trim: pwd session clone (protected): ${invoked_from}"
  else
    echo "nutup trim: pwd session clone: none"
    echo "nutup trim:   (not inside a session clone -- run from the clone you want to keep)"
  fi
  echo "nutup trim: session clones (${#all_clones_list[@]}):"
  for clone in "${all_clones_list[@]}"; do
    mtime=$(_nutup_trim_clone_mtime "$clone")
    head=$(git -C "$clone" log -1 --oneline 2>/dev/null || echo "(no commits)")
    markers=""
    _nutup_trim_clone_dirty "$clone" && markers="${markers} dirty"
    _nutup_trim_clone_unlanded "$clone" "$canonical" && markers="${markers} unlanded"
    printf 'nutup trim:   %s\n' "$clone"
    printf 'nutup trim:     HEAD %s  .git-mtime=%s%s\n' "$head" "$mtime" "$markers"
  done
  echo "nutup trim: plan (keep-latest=${keep_latest}):"
  for clone in "${all_clones_list[@]}"; do
    if _nutup_trim_clone_unlanded "$clone" "$canonical"; then
      printf 'nutup trim:   keep (unlanded): %s\n' "$clone"
      continue
    fi
    if _nutup_trim_kept_contains "$clone" "${kept[@]}"; then
      reason="newest .git mtime (keep-latest)"
      [[ "$clone" == "$invoked_from" ]] && reason="pwd session clone + keep-latest"
      printf 'nutup trim:   keep (%s): %s\n' "$reason" "$clone"
      continue
    fi
    if [[ "$dry_run" == 1 ]]; then
      printf 'nutup trim:   prune (dry-run): %s\n' "$clone"
    else
      printf 'nutup trim:   prune: %s\n' "$clone"
    fi
  done
  printf 'nutup trim:   consolidation target: %s\n' "$rollover_target"

  if [[ "$dry_run" == 1 ]]; then
    echo "nutup trim: dry-run -- not consolidated or pruned (re-run without --dry-run to confirm)"
  elif [[ "$yes" != 1 ]]; then
    read -r -p "nutup trim: consolidate and prune ${#to_archive[@]} session clone(s) for ${name}? [y/N] " line
    [[ "$line" == [yY] || "$line" == [yY][eE][sS] ]] || {
      echo "nutup trim: aborted (not consolidated or pruned)"
      return 1
    }
  fi

  for clone in "${to_archive[@]}"; do
    dirty=0
    unlanded=0
    _nutup_trim_clone_dirty "$clone" && dirty=1
    _nutup_trim_clone_unlanded "$clone" "$canonical" && unlanded=1

    if [[ "$unlanded" == 1 ]]; then
      subjects=$(git -C "$clone" log --oneline origin/main..HEAD 2>/dev/null | head -5)
      echo "nutup trim:   kept (unlanded): ${clone}"
      [[ -n "$subjects" ]] && echo "nutup trim:     ${subjects}"
      kept_unlanded=$((kept_unlanded + 1))
      continue
    fi

    if [[ "$dirty" == 1 ]]; then
      if [[ "$no_rollover" == 1 ]]; then
        echo "nutup trim:   kept (dirty, --no-rollover): ${clone}"
        kept_dirty=$((kept_dirty + 1))
        continue
      fi
      if [[ "$dry_run" == 1 ]]; then
        echo "nutup trim:   [dry-run] would consolidate dirty: ${clone} -> ${rollover_target}"
      else
        read -r files conflicts < <(_nutup_trim_rollover "$clone" "$rollover_target")
        if [[ "$conflicts" == 1 ]]; then
          echo "nutup trim:   consolidated: ${clone} (${files} file(s); conflicts left for agent)"
        else
          echo "nutup trim:   consolidated: ${clone} (${files} file(s))"
        fi
        rolled=$((rolled + 1))
      fi
    fi

    if _nutup_trim_archive_clone "$clone" "$archive_dir" "$dry_run"; then
      archived=$((archived + 1))
    else
      return 1
    fi
  done

  if [[ "$dry_run" == 1 ]]; then
    echo "nutup trim: ${name} -- dry-run: ${archived} would prune, ${rolled} would consolidate -> ${rollover_target}, ${kept_unlanded} kept (unlanded), ${kept_dirty} kept (dirty)"
  else
    echo "nutup trim: ${name} -- consolidated and pruned: ${rolled} consolidated -> ${rollover_target}, ${archived} pruned, ${kept_unlanded} kept (unlanded), ${kept_dirty} kept (dirty)"
    echo "nutup trim:   prune archives in ${archive_dir}"
  fi
  return 0
}

nutup_trim() {
  local repo="" all=0 dry_run=0 yes=0 no_rollover=0 keep_latest=1 archive_dir=""
  local name host failed=0 ok=0

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
nutup trim -- consolidate and prune stale agent session clones for a consumer

  nutup trim                 infer consumer from pwd
  nutup trim <project>       named consumer
  nutup trim --all           every configured consumer
  nutup trim --dry-run       print plan only (never consolidates or prunes)
  nutup trim --yes           skip confirmation prompt (still consolidates/prunes)
  nutup trim --no-rollover   keep dirty older clones instead of consolidating
  nutup trim --keep-latest N keep N newest clones (default 1)
  nutup trim --archive-dir <path>

Consolidates uncommitted work from older clones into the kept clone, then prunes
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
          echo "nutup trim: --keep-latest requires a number" >&2
          return 1
        }
        ;;
      --archive-dir)
        shift
        archive_dir="${1:-}"
        [[ -n "$archive_dir" ]] || {
          echo "nutup trim: --archive-dir requires a path" >&2
          return 1
        }
        ;;
      -*)
        echo "nutup trim: unknown option: $1 (try: nutup trim --help)" >&2
        return 1
        ;;
      *)
        if [[ -n "$repo" ]]; then
          echo "nutup trim: unexpected argument: $1" >&2
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
      if _nutup_trim_one "$name" "$dry_run" "$yes" "$no_rollover" "$keep_latest" "$archive_dir"; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done < <(_nutupyall_consumer_roots | sort -u)
    echo "nutup trim: done -- ${ok} ok, ${failed} failed"
    [[ "$failed" -eq 0 ]]
    return $?
  fi

  if [[ -z "$repo" ]]; then
    repo=$(_nut_resolve_sync_target "" 2>/dev/null | xargs basename 2>/dev/null) || {
      echo "nutup trim: not in a git repo (try: nutup trim <name>)" >&2
      return 1
    }
  fi

  _nutup_trim_one "$repo" "$dry_run" "$yes" "$no_rollover" "$keep_latest" "$archive_dir"
}

# Run only from agentstartstack canonical local repo; nutup template, refresh consumers.
_nutupyall_assert_here() {
  local here sync_root

  here=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "nutupyall: not in a git repo" >&2
    return 1
  }
  here=$(readlink -f "$here")

  sync_root=$(_nut_sync_root agentstartstack) || {
    echo "nutupyall: agentstartstack canonical local repo not found" >&2
    return 1
  }

  if [[ "$here" != "$sync_root" ]]; then
    echo "nutupyall: run only from agentstartstack canonical local repo: ${sync_root}" >&2
    return 1
  fi
}

_nutupyall_consumer_roots() {
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
# flight). nutupyall defers a consumer's auto-bump while any of its clones is
# busy, so committing + pushing the bump cannot diverge the clone (its next nut
# would otherwise be a non-fast-forward and clobber the agent mid-work).
# List all session clones for a consumer (one absolute path per line), matched by
# git origin URL so no worktree directory-naming scheme is assumed.
_nutupyall_session_clones() {
  local name="$1" canonical origin
  canonical=$(_nut_sync_root "$name") || return 0
  origin=$(git -C "$canonical" remote get-url origin 2>/dev/null) || return 0
  _agentstartstack_clones_for_origin "$origin"
}

# Echo in-flight session clones for a consumer, one per line: "<clone><TAB><reason>".
# In-flight = uncommitted changes, or commits ahead of local-sync/main. An
# in-flight clone would turn into a non-fast-forward on its next nut if canonical
# advanced, so nutupyall does not auto-commit a consumer's bump while any of its
# clones is in-flight -- it drops a watch file instead (see _nutupyall_flag_clone).
_nutupyall_busy_sessions() {
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
  done < <(_nutupyall_session_clones "$name")
}

# Drop a gitignored watch file in a session clone telling its agent to pull the
# pending .agentstartstack bump into the clone before its next commit. The file
# lives at the clone root and is excluded via .git/info/exclude, so it never
# shows in git status, is never committed, and survives reset --hard + clean -fd.
_nutupyall_flag_clone() {
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
  agentstartstack/workflow.md -> "The .agentstartstack-bump watch file"

Quick start:
  git submodule update --init --recursive --remote .agentstartstack
  git add .agentstartstack && rm .agentstartstack-bump

Written by nutupyall at $(date -Is).
EOF
}

nutupyall()
{
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
nutupyall -- local-sync and push agentstartstack, refresh .agentstartstack in consumer repos

Run only from the agentstartstack canonical local repo (not a session clone).

For each consumer repo:
  - No in-flight session clone -> if the delta is action-free, auto-commit the
    .agentstartstack bump and push origin main. If the delta carries any
    CONSUMER-ACTION, do NOT auto-commit (would skip the actions); report it under
    "need agent (actions)" and leave it for an agent session to reconcile.
  - In-flight session clone(s) (uncommitted changes or ahead of canonical) ->
    do NOT touch canonical (would non-fast-forward an agent's nut). Instead drop
    a gitignored .agentstartstack-bump watch file in every clone; the bump rides
    along on the agent's next commit and reaches canonical via nut.

  nutupyall
  nutupyall --help
EOF
    return 0
  fi

  if [[ -n "${1:-}" ]]; then
    echo "nutupyall: takes no arguments (try: nutupyall --help)" >&2
    return 1
  fi

  _nutupyall_assert_here || return 1

  nutup || return 1

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

    busy=$(_nutupyall_busy_sessions "$name")
    if [[ -n "$busy" ]]; then
      sub_sha="$as_sha"
      n_flag=0
      while IFS= read -r clone; do
        [[ -n "$clone" ]] || continue
        _nutupyall_flag_clone "$clone" "$sub_sha"
        n_flag=$((n_flag + 1))
      done < <(_nutupyall_session_clones "$name")
      echo "nutupyall: ${name} -- in-flight session(s); flagged ${n_flag} clone(s) for bump -> ${sub_sha}, rides along on next agent commit/nut" >&2
      while IFS=$'\t' read -r iclone ireason; do
        [[ -n "$iclone" ]] && echo "nutupyall:   in-flight: ${iclone} (${ireason})" >&2
      done <<< "$busy"
      flagged=$((flagged + 1))
    else
      old_sha=$(git -C "${host}/.agentstartstack" rev-parse HEAD 2>/dev/null)
      echo "nutupyall: ${name} -- submodule update --remote .agentstartstack"
      if ! git -C "$host" submodule update --init --recursive --remote .agentstartstack; then
        echo "nutupyall:   ERROR updating submodule in ${name}" >&2
        failed=$((failed + 1))
      elif [[ -z "$(git -C "$host" status --porcelain -- .agentstartstack 2>/dev/null)" ]]; then
        echo "nutupyall:   ${name} already current"
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
          echo "nutupyall:   ${name} -- delta ${old_sha:0:7}..${new_sha:0:7} carries CONSUMER-ACTION(s); NOT auto-bumped." >&2
          echo "nutupyall:     start an agent session for ${name} so it reads the delta and reconciles." >&2
          needs_agent=$((needs_agent + 1))
        else
          sub_sha=$(git -C "${host}/.agentstartstack" rev-parse --short HEAD 2>/dev/null)
          echo "nutupyall:   committing bump to ${sub_sha} in ${name} (action-free delta)"
          if ! git -C "$host" commit -m "Bump .agentstartstack to ${sub_sha}" -- .agentstartstack; then
            echo "nutupyall:   ERROR committing bump in ${name}" >&2
            failed=$((failed + 1))
          elif ! git -C "$host" push origin main; then
            echo "nutupyall:   WARN committed bump but origin push failed in ${name}" >&2
            failed=$((failed + 1))
          else
            bumped=$((bumped + 1))
          fi
        fi
      fi
    fi

    if _nutup_trim_autotrim_enabled "$host"; then
      if nutup_trim "$name" --yes; then
        echo "nutupyall: ${name} -- consolidated and pruned" >&2
      else
        echo "nutupyall: ${name} -- trim failed (logged; continuing)" >&2
        failed=$((failed + 1))
      fi
    else
      echo "nutupyall: ${name} -- autotrim disabled (NUTUPYALL_AUTOTRIM=0)" >&2
    fi
  done < <(_nutupyall_consumer_roots | sort -u)

  echo "nutupyall: done -- ${bumped} bumped, ${current} already current, ${flagged} flagged (in-flight), ${needs_agent} need agent (actions), ${failed} failed"
  [[ "$failed" -eq 0 ]]
}
