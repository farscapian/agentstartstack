# nut -- local-sync with canonical local repo

Human-side helper for the AI git workflow step **local-sync** (session clone -> canonical local repo via the `local-sync` remote). Agents commit in the session clone; the human runs `nut` to local-sync with the canonical local repo, reviews, then `git push origin main`.

**Canonical install:** `~/.bash_aliases` (not tracked in this repo). The copy below is documentation of record -- update `agentstartstack/nut.md` in agentstartstack when the function changes.

## Why "nut"

Canonical backronym: **N**ewest commit **U**ntil **T**ransferred.

Performs local-sync from the matching session clone (Claude or Grok) into the canonical local repo (`SYNC_REPO` in host `.agentstartstack.env`; default `~/Sync/mini_projects/<repo>`). Short to type, works for every mini-project.

Alt backronyms (HEAD is the tip of the current branch, so the puns write themselves):

- `nut` -- **N**udge **U**ntil **T**ip: advance the branch until the newest commit lands on HEAD.
- `nutup` -- **N**udge **U**ntil **T**ip's **U**p, then **P**ush: get HEAD current locally, then push it upstream -- the exact two-step local-sync-then-publish semantics.

Retired names: `s2s`, `land`, `s2ps`, `s2is`, `push`, `nut push`.

## Usage

```bash
nut                 # local-sync with canonical local repo (infer from pwd)
nut iotstack        # explicit repo name, any pwd
nutup               # local-sync, then git push origin main
nutup iotstack      # local-sync for iotstack, then push
nutupyall           # nutup agentstartstack, refresh consumer submodules
nut --help
nutup --help
nutupyall --help
```

**`nut`** -- local-sync only: session clone -> canonical local repo. Human reviews before publishing.

**`nutup`** -- full human handoff: local-sync with the canonical local repo, then publish to `origin/main`. Agents never run `nutup` themselves.

**`nutupyall`** -- template publish plus submodule refresh. Run only from the agentstartstack canonical local repo (not a session clone, not another repo). Local-sync and push agentstartstack, then finds every host canonical local repo whose `.gitmodules` references `farscapian/agentstartstack` and runs `git submodule update --init --recursive --remote .agentstartstack`. Consumer working trees pick up the new template; host repos still need a committed submodule bump to record the SHA on `origin/main`.

**Conventions**

| Item | Path |
|------|------|
| Canonical local repo | `SYNC_REPO` in `.agentstartstack.env` (default: `~/Sync/mini_projects/<name>`) |
| Session clones | `~/.claude/worktrees/mini-projects-<name>/*` |
| | `~/.grok/worktrees/mini-projects-<name>/*` |

Session clones are matched by `origin` URL so repos cannot cross-contaminate. Among matches, the clone with the newest commit on `main` wins.

## Guards

`nut` refuses to run while long-running tools are active on the canonical local repo (local-sync updates its working tree via `receive.denyCurrentBranch = updateInstead`):

| Repo | Blocks while |
|------|----------------|
| iotstack | `iotstack` / `iotstack.sh` running |
| printstack | `printstack` / `printstack.sh` running |
| wrtstack | `wrtstack (build|flash)` running |

To add a guard for a new project, extend `_nut_guard_active_sessions` in `~/.bash_aliases` (see Source below).

## Workflow

1. Agent commits in session clone
2. Human reviews (optional): `nut` local-syncs with the canonical local repo
3. Human publishes: `git push origin main` from the canonical local repo, or combine: `nutup`

Agents never run `nut` or `nutup` unless the human explicitly asks.

See [workflow.md](workflow.md) for session align, agent clone paths, and full git policy.

## Source (`~/.bash_aliases`)

```bash
#!/bin/bash

# Retired names -- clear if still loaded in this shell.
unset -f land s2s s2ps s2is push 2>/dev/null

# nut / nutup -- Newest commit Until Transferred
#
# Usage:
#   nut              # local-sync with canonical local repo
#   nutup            # local-sync, then git push origin main
#   nutup iotstack   # explicit repo + local-sync + push
#   nutupyall        # nutup agentstartstack, refresh consumer submodules

_nut_sync_root() {
  local repo_name="$1"

  if [[ -d "${HOME}/Sync/mini_projects/${repo_name}/.git" ]]; then
    printf '%s/Sync/mini_projects/%s\n' "$HOME" "$repo_name"
    return 0
  fi
  if [[ -d "${HOME}/Sync/${repo_name}/.git" ]]; then
    printf '%s/Sync/%s\n' "$HOME" "$repo_name"
    return 0
  fi

  return 1
}

_nut_sync_target_from_worktree() {
  local wt="$1" parent_base

  if git -C "$wt" remote get-url local-sync &>/dev/null 2>&1; then
    readlink -f "$(git -C "$wt" remote get-url local-sync)"
    return 0
  fi

  parent_base=$(basename "$(dirname "$wt")")
  if [[ "$parent_base" =~ ^mini-projects-(.+)$ ]]; then
    _nut_sync_root "${BASH_REMATCH[1]}"
    return $?
  fi

  return 1
}

_nut_guard_active_sessions() {
  local sync_target="$1"

  case "$sync_target" in
    */mini_projects/iotstack|*/Sync/iotstack)
      if pgrep -af '(/iotstack\.sh|/iotstack) ' >/dev/null 2>&1; then
        echo "nut: iotstack is running -- wait for it to finish" >&2
        return 1
      fi
      ;;
    */mini_projects/printstack|*/Sync/printstack)
      if pgrep -af '(printstack\.sh|/printstack) ' >/dev/null 2>&1; then
        echo "nut: printstack is running -- wait for it to finish" >&2
        return 1
      fi
      ;;
    */mini_projects/wrtstack|*/Sync/wrtstack)
      if pgrep -af 'wrtstack (build|flash)' >/dev/null 2>&1; then
        echo "nut: wrtstack is running -- wait for it to finish" >&2
        return 1
      fi
      ;;
  esac

  return 0
}

_nut_push() {
  local sync_target="$1"
  local origin_target best_dir="" best_time=0 candidate t origin_wt commit repo_name

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

  for candidate in \
      "${HOME}/.claude/worktrees/mini-projects-${repo_name}/"*/ \
      "${HOME}/.grok/worktrees/mini-projects-${repo_name}/"*/; do
    [[ -d "${candidate}.git" ]] || continue
    candidate=$(readlink -f "$candidate")

    origin_wt=$(git -C "$candidate" remote get-url origin 2>/dev/null) || continue
    [[ "$origin_wt" == "$origin_target" ]] || continue

    t=$(git -C "$candidate" log -1 --format=%ct 2>/dev/null) || continue
    if [[ "$t" -gt "$best_time" ]]; then
      best_time=$t
      best_dir=$candidate
    fi
  done

  if [[ -z "$best_dir" ]]; then
    echo "nut: no session clone for ${repo_name}" >&2
    return 1
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
}

_nut_resolve_sync_target() {
  local repo_arg="${1:-}"
  local here sync_target

  if [[ -n "$repo_arg" ]]; then
    sync_target=$(_nut_sync_root "$repo_arg") || {
      echo "nut: no canonical local repo found for: ${repo_arg}" >&2
      return 1
    }
  else
    here=$(git rev-parse --show-toplevel 2>/dev/null) || {
      echo "nut: not in a git repo (try: nut <name>)" >&2
      return 1
    }
    here=$(readlink -f "$here")

    if [[ "$here" == *"/.grok/worktrees/"* || "$here" == *"/.claude/worktrees/"* ]]; then
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
  local repo_arg="${1:-}"

  if [[ "$repo_arg" == "-h" || "$repo_arg" == "--help" ]]; then
    cat <<'EOF'
nut -- Newest commit Until Transferred

Perform local-sync with the canonical local repo (session clone -> local-sync remote).

  nut                 infer repo from pwd
  nut <name>          e.g. nut printstack, nut iotstack, nut wrtstack
  nutup               local-sync, then git push origin main
  nutup <name>        local-sync for <name>, then push
  nutupyall           nutup agentstartstack, refresh .agentstartstack submodules

Canonical:   ~/Sync/mini_projects/<name>  (or ~/Sync/<name>; see SYNC_REPO)
Session:     ~/.claude/worktrees/mini-projects-<name>/*
             ~/.grok/worktrees/mini-projects-<name>/*
EOF
    return 0
  fi

  local sync_target
  sync_target=$(_nut_resolve_sync_target "$repo_arg") || return 1
  _nut_push "$sync_target"
}

nutup()
{
  local repo_arg="${1:-}"

  if [[ "$repo_arg" == "-h" || "$repo_arg" == "--help" ]]; then
    cat <<'EOF'
nutup -- local-sync with canonical local repo, then git push origin main

  nutup               infer repo from pwd
  nutup <name>        e.g. nutup printstack, nutup wrtstack
EOF
    return 0
  fi

  local sync_target
  sync_target=$(_nut_resolve_sync_target "$repo_arg") || return 1
  _nut_push "$sync_target" || return 1
  echo "nutup: ${sync_target} -> origin main"
  git -C "$sync_target" push origin main
}

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
  local search_root candidate gitmodules

  for search_root in "${HOME}/Sync/mini_projects" "${HOME}/Sync"; do
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

nutupyall()
{
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'EOF'
nutupyall -- local-sync and push agentstartstack, refresh .agentstartstack in consumer repos

Run only from the agentstartstack canonical local repo (not a session clone).

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

  local host
  while IFS= read -r host; do
    [[ -n "$host" ]] || continue
    echo "nutupyall: ${host} -- submodule update --init --recursive --remote .agentstartstack"
    git -C "$host" submodule update --init --recursive --remote .agentstartstack || return 1
  done < <(_nutupyall_consumer_roots | sort -u)
}
```