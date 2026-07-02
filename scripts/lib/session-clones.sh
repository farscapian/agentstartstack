#!/usr/bin/env bash
# session-clones.sh -- single source for agent session worktree discovery.
#
# All ass commands that need session worktrees MUST call agent_session_clones_list().
# Same function, same order everywhere (newest commit on main first; ass status #1).
# Worktrees are matched by git origin URL under AGENT_SESSION_CLONE_PARENT (any depth
# up to 6 path segments below each parent; no directory-naming scheme assumed).
#
# ass does NOT create worktrees -- grok and claude create their own under
# ~/.grok/worktrees and ~/.claude/worktrees. A discovered worktree may be a full
# clone (.git is a directory) or a linked git worktree (.git is a gitfile pointing
# into <canonical>/.git/worktrees/); both are supported. Consumer .agentstartstack
# submodule checkouts (.git -> .git/modules/) are excluded. Make an agent worktree
# ass-aware with 'ass adopt'; list unrecognized ones with 'ass discover'.
#
# shellcheck shell=bash

_agent_session_clone_parents_default() {
  printf '%s:%s\n' \
    "${HOME}/.claude/worktrees" \
    "${HOME}/.grok/worktrees"
}

if [[ -z "${AGENT_SESSION_CLONE_PARENT:-}" ]]; then
  AGENT_SESSION_CLONE_PARENT=$(_agent_session_clone_parents_default)
fi
export AGENT_SESSION_CLONE_PARENT

# Absolute git dir for a repo or worktree. For a linked git worktree (.git is a
# gitfile) this is <canonical>/.git/worktrees/<name>, NOT <path>/.git -- so ass
# markers (agentstartstack-session-init/-agent) must be read/written here, not under
# <path>/.git which is a file. Falls back to <path>/.git if git cannot resolve it.
_agent_session_gitdir() {
  git -C "$1" rev-parse --absolute-git-dir 2>/dev/null || printf '%s\n' "${1}/.git"
}

# True if $1 is a LINKED git worktree (git dir is <canonical>/.git/worktrees/<name>),
# which shares canonical's config/remotes -- so ass must NOT harden origin or push a
# local-sync handoff there. False for an independent full clone (its own .git dir).
_agent_session_is_linked_worktree() {
  case "$(_agent_session_gitdir "$1")" in
    */.git/worktrees/*) return 0 ;;
    *) return 1 ;;
  esac
}

# True for agent session worktree roots: a full clone (.git is a directory) or a
# linked git worktree (.git is a gitfile -> <canonical>/.git/worktrees/<name>).
# Excludes consumer .agentstartstack submodule checkouts (git dir is .git/modules/*)
# and any dir literally named .agentstartstack. Origin matching is enforced by the
# caller (agent_session_clones_list), so no directory-naming scheme is assumed.
_agent_session_clone_is_valid() {
  local candidate="$1"
  local gitdir

  candidate=$(readlink -f "$candidate")
  [[ -n "$candidate" && -d "$candidate" ]] || return 1
  [[ "$(basename "$candidate")" != ".agentstartstack" ]] || return 1
  [[ -e "${candidate}/.git" ]] || return 1

  # Resolve the real git dir to classify: full clone (.git dir), linked worktree
  # (.git/worktrees/<name>), or submodule checkout (.git/modules/<name> -- excluded).
  gitdir=$(git -C "$candidate" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  case "$gitdir" in
    */.git/modules/*) return 1 ;;
  esac
  return 0
}

# Session-age key for tiebreaking agent_session_clones_list (newest session first):
# the init-marker time, else a numeric worktree-dir basename, else the git-dir mtime.
# Resolves the real git dir so linked worktrees (.git is a gitfile) work too.
# Returns a single integer.
_agent_session_clone_sort_key() {
  local clone="$1"
  local v base gitdir marker
  gitdir=$(_agent_session_gitdir "$clone")
  marker="${gitdir}/agentstartstack-session-init"
  if [[ -f "$marker" ]]; then
    v=$(tr -d '[:space:]' < "$marker" 2>/dev/null)
    [[ "$v" =~ ^[0-9]+$ ]] && { printf '%s\n' "$v"; return 0; }
  fi
  base=$(basename "$clone")
  if [[ "$base" =~ ^[0-9]+$ ]]; then printf '%s\n' "$base"; return 0; fi
  stat -c %Y "$gitdir" 2>/dev/null || echo 0
}

# agent_session_clones_list WANT
#
# WANT: canonical git origin URL (exact string match to each worktree's origin remote).
# Prints absolute worktree paths, one per line, newest commit on main first. Deduped.
# Full clones and linked git worktrees; not nested .agentstartstack submodules.
# Ties on commit time (e.g. all aligned to the same canonical HEAD) break by newest
# session, so ass status #1 is the active/most-recent worktree.
agent_session_clones_list() {
  local want="$1" parents base candidate got gitref
  declare -A seen=()
  local -a clones=()

  [[ -n "$want" ]] || return 0

  parents="${AGENT_SESSION_CLONE_PARENT:-$(_agent_session_clone_parents_default)}"
  local IFS=:
  for base in $parents; do
    [[ -n "$base" && -d "$base" ]] || continue
    # Match .git as a directory (full clone) OR a file (linked worktree gitfile).
    while IFS= read -r gitref; do
      [[ -n "$gitref" ]] || continue
      candidate=$(readlink -f "$(dirname "$gitref")")
      [[ -n "$candidate" ]] || continue
      [[ -n "${seen[$candidate]:-}" ]] && continue
      _agent_session_clone_is_valid "$candidate" || continue
      got=$(git -C "$candidate" remote get-url origin 2>/dev/null) || continue
      if [[ "$got" == "$want" ]]; then
        seen[$candidate]=1
        clones+=("$candidate")
      fi
    done < <(
      find "$base" -mindepth 1 -maxdepth 6 \( -type d -o -type f \) -name .git \
        ! -path '*/.git/*' -printf '%p\n' 2>/dev/null
    )
  done
  unset IFS

  [[ ${#clones[@]} -gt 0 ]] || return 0

  for candidate in "${clones[@]}"; do
    printf '%s %s %s\n' \
      "$(git -C "$candidate" log -1 --format=%ct main 2>/dev/null || echo 0)" \
      "$(_agent_session_clone_sort_key "$candidate")" \
      "$candidate"
  done | sort -rn -k1,1 -k2,2 | awk '{print $3}'
}