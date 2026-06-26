#!/usr/bin/env bash
# session-clones.sh -- single source for agent session clone discovery.
#
# All ass/nut commands that need session clones MUST call agent_session_clones_list().
# Same function, same order everywhere (newest commit on main first; ass status #1).
# Clones are matched by git origin URL under AGENT_SESSION_CLONE_PARENT (any depth
# up to 5 path segments below each parent; no directory-naming scheme assumed).
#
# ass new ALWAYS creates clones under ASS_NEW_SESSION_CLONE_ROOT/<repo>/<timestamp>.
#
# shellcheck shell=bash

ASS_NEW_SESSION_CLONE_ROOT="${HOME}/.ass/worktrees"
export ASS_NEW_SESSION_CLONE_ROOT

_agent_session_clone_parents_default() {
  printf '%s:%s:%s\n' \
    "${ASS_NEW_SESSION_CLONE_ROOT}" \
    "${HOME}/.claude/worktrees" \
    "${HOME}/.grok/worktrees"
}

if [[ -z "${AGENT_SESSION_CLONE_PARENT:-}" ]]; then
  AGENT_SESSION_CLONE_PARENT=$(_agent_session_clone_parents_default)
fi
export AGENT_SESSION_CLONE_PARENT

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

# Session-age key for tiebreaking agent_session_clones_list (newest session first):
# the init-marker time, else a numeric clone-dir basename (ass new session id),
# else the .git mtime. Returns a single integer.
_agent_session_clone_sort_key() {
  local clone="$1"
  local v base marker="${clone}/.git/agentstartstack-session-init"
  if [[ -f "$marker" ]]; then
    v=$(tr -d '[:space:]' < "$marker" 2>/dev/null)
    [[ "$v" =~ ^[0-9]+$ ]] && { printf '%s\n' "$v"; return 0; }
  fi
  base=$(basename "$clone")
  if [[ "$base" =~ ^[0-9]+$ ]]; then printf '%s\n' "$base"; return 0; fi
  stat -c %Y "${clone}/.git" 2>/dev/null || echo 0
}

# agent_session_clones_list WANT
#
# WANT: canonical git origin URL (exact string match to each clone's origin remote).
# Prints absolute clone paths, one per line, newest commit on main first. Deduped.
# Only full session clones (.git directory); not nested .agentstartstack submodules.
# Ties on commit time (e.g. all clones aligned to the same canonical HEAD) break by
# newest session, so ass status #1 is the active/most-recent clone.
agent_session_clones_list() {
  local want="$1" parents base candidate got gitdir
  declare -A seen=()
  local -a clones=()

  [[ -n "$want" ]] || return 0

  # Always search ass-new root; append configured parents (may be a user override).
  parents="${ASS_NEW_SESSION_CLONE_ROOT}"
  if [[ -n "${AGENT_SESSION_CLONE_PARENT:-}" ]]; then
    parents="${parents}:${AGENT_SESSION_CLONE_PARENT}"
  fi
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
    printf '%s %s %s\n' \
      "$(git -C "$candidate" log -1 --format=%ct main 2>/dev/null || echo 0)" \
      "$(_agent_session_clone_sort_key "$candidate")" \
      "$candidate"
  done | sort -rn -k1,1 -k2,2 | awk '{print $3}'
}