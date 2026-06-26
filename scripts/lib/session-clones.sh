#!/usr/bin/env bash
# session-clones.sh -- single source for agent session clone discovery.
#
# All ass/nut commands that need session clones MUST call agent_session_clones_list().
# Same function, same order everywhere (newest commit on main first; ass status #1).
# Clones are matched by git origin URL under AGENT_SESSION_CLONE_PARENT (any depth
# up to 5 path segments below each parent; no directory-naming scheme assumed).
#
# shellcheck shell=bash

: "${AGENT_SESSION_CLONE_PARENT:=${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"

# Repo directory name from origin URL (e.g. agentstartstack.git -> agentstartstack).
_agent_session_clone_repo_name() {
  local origin="$1" name
  name=$(basename "$origin")
  name="${name%.git}"
  printf '%s\n' "$name"
}

# True for agent session clone roots (full clones with .git as a directory).
# Excludes consumer .agentstartstack submodule checkouts (.git is a gitfile).
# Requires .../<repo-name>/... so reconcile/aux clones under consumer trees are skipped.
_agent_session_clone_is_valid() {
  local candidate="$1" origin="${2:-}"
  local repo_name

  candidate=$(readlink -f "$candidate")
  [[ -n "$candidate" && -d "$candidate" ]] || return 1
  [[ "$(basename "$candidate")" != ".agentstartstack" ]] || return 1
  [[ -d "${candidate}/.git" ]] || return 1
  if [[ -n "$origin" ]]; then
    repo_name=$(_agent_session_clone_repo_name "$origin")
    [[ -n "$repo_name" ]] || return 1
    [[ "$candidate" == */"${repo_name}"/* ]] || return 1
  fi
  return 0
}

# agent_session_clones_list WANT
#
# WANT: canonical git origin URL (exact string match to each clone's origin remote).
# Prints absolute clone paths, one per line, newest commit on main first. Deduped.
# Only full session clones (.git directory); not nested .agentstartstack submodules.
agent_session_clones_list() {
  local want="$1" parents base candidate got gitdir
  declare -A seen=()
  local -a clones=()

  [[ -n "$want" ]] || return 0

  parents="${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"
  local IFS=:
  for base in $parents; do
    [[ -n "$base" && -d "$base" ]] || continue
    while IFS= read -r gitdir; do
      [[ -n "$gitdir" ]] || continue
      candidate=$(readlink -f "$(dirname "$gitdir")")
      [[ -n "$candidate" ]] || continue
      [[ -n "${seen[$candidate]:-}" ]] && continue
      _agent_session_clone_is_valid "$candidate" "$want" || continue
      got=$(git -C "$candidate" remote get-url origin 2>/dev/null) || continue
      if [[ "$got" == "$want" ]]; then
        seen[$candidate]=1
        clones+=("$candidate")
      fi
    done < <(
      find "$base" -mindepth 1 -maxdepth 5 -type d -name .git \
        ! -path '*/.git/*' -printf '%p\n' 2>/dev/null
    )
  done
  unset IFS

  [[ ${#clones[@]} -gt 0 ]] || return 0

  for candidate in "${clones[@]}"; do
    printf '%s %s\n' "$(git -C "$candidate" log -1 --format=%ct main 2>/dev/null || echo 0)" "$candidate"
  done | sort -rn -k1,1 | awk '{print $2}'
}