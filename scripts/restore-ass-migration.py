#!/usr/bin/env python3
"""Restore ass CLI migration deleted from canonical. Run from repo root.

  python3 scripts/restore-ass-migration.py

Reads nut-aliases.sh, session transcript (updates.jsonl), and writes the full
ass migration with incremental git commits.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TRANSCRIPT = Path(
    os.environ.get(
        "ASS_RESTORE_TRANSCRIPT",
        "/home/derek/.grok/sessions/%2Fhome%2Fderek%2F.grok%2Fworktrees%2F"
        "mini-projects-agentstartstack%2Fconsolidate/"
        "019f048a-715e-7293-a258-44eb68be0243/updates.jsonl",
    )
)

ASS_INJECT = r'''
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
'''


def run(cmd: list[str], cwd: Path = REPO) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


def git(*args: str) -> None:
    run(["git", *args])


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    print(f"Wrote {path.relative_to(REPO)} ({len(content.splitlines())} lines)")


def extract_from_transcript(filename: str) -> str | None:
    if not TRANSCRIPT.is_file():
        return None
    best = None
    with TRANSCRIPT.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            upd = obj.get("params", {}).get("update", {})
            for block in upd.get("content") or []:
                if not isinstance(block, dict) or block.get("type") != "diff":
                    continue
                if not block.get("path", "").endswith(filename):
                    continue
                nt = block.get("newText")
                if nt and (best is None or len(nt) > len(best)):
                    best = nt
            raw = upd.get("rawInput") or {}
            if raw.get("path", "").endswith(filename) and raw.get("contents"):
                c = raw["contents"]
                if best is None or len(c) > len(best):
                    best = c
    return best


def transform_nut_to_ass(src: str) -> str:
    # Header + cli-log
    header = '''#!/usr/bin/env bash
# ass-aliases.sh -- ass CLI implementation library (sourced by scripts/ass.sh).
#
# Command entry point: scripts/ass.sh. install-shell-aliases.sh installs a thin
# ass() wrapper only. docs/ass.md documents usage.
#
# shellcheck shell=bash

# Retired names -- clear if still loaded in this shell.
unset -f land s2s s2ps s2is push nut nutup nutupyall nutup_trim dropit assup assupyall assitup 2>/dev/null

'''
    body = src
    if body.startswith("#!/"):
        body = body.split("\n", 1)[1]
        body = re.sub(r"^#.*\n", "", body, count=10)

    # Insert after AGENT_SESSION_CLONE_PARENT export block
    cli_block = '''
# Shared CLI logging (docs/cli.md, conventions.md -- Script output).
_ASS_ALIASES_LIB_DIR=$(
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
)
# shellcheck source=cli-log.sh
source "${_ASS_ALIASES_LIB_DIR}/cli-log.sh"
: "${AGENTSTARTSTACK_CLI_LOG_PREFIX:=ass}"
: "${AGENTSTARTSTACK_CLI_LOG_DIR:=${HOME}/.agentstartstack/logs}"

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

'''
    body = body.replace(
        "export AGENT_SESSION_CLONE_PARENT\n",
        "export AGENT_SESSION_CLONE_PARENT\n" + cli_block,
        1,
    )

    repl = [
        ("_nutupyall_", "_ass_up_all_"),
        ("_nutup_trim_", "_ass_up_trim_"),
        ("_nutup_", "_ass_up_"),
        ("nutupyall", "ass_up_all"),
        ("nutup_trim", "ass_up_trim"),
        ("nutup trim", "ass up trim"),
        ("nutup()", "ass_up()"),
        ("_nut_", "_ass_"),
        ("_NUT_", "_ASS_"),
        ("nut:", "ass:"),
        ("nut.md", "ass.md"),
        ("agentstartstack/", "docs/"),
        ("agentstartstack-nut-last", "agentstartstack-ass-last"),
        ("NUTUPYALL_AUTOTRIM", "ASS_UP_ALL_AUTOTRIM"),
        ("# nut / nutup", "# ass / ass up"),
        ("nut-aliases", "ass-aliases"),
        ("nutupyall's", "ass up --all's"),
        ("nut()", "ass()"),
        ("Written by nutupyall", "Written by ass up --all"),
        ("next nut", "next ass"),
        ("last nut", "last ass"),
        ("via nut", "via ass"),
        ("hand off with nut", "hand off with ass"),
        ("then nut.", "then ass."),
    ]
    for a, b in repl:
        body = body.replace(a, b)

    body = re.sub(r"alias assitup=.*\n", "", body)
    body = re.sub(r"alias nutitup=.*\n", "", body)
    body = re.sub(r"# Alias: nutitup.*\n\n?", "", body)

    # pwd-only: reject repo-name positional args
    body = body.replace(
        "# Parse nut/nutup args: optional -f/--force, optional repo name, -h/--help.\n"
        "# Sets _ASS_PARSE_FORCE (0|1) and _ASS_PARSE_REPO (name or empty).\n"
        "_ass_parse_args() {\n"
        "  _ASS_PARSE_FORCE=0\n"
        '  _ASS_PARSE_REPO=""\n'
        "  _ASS_PARSE_HELP=0\n",
        "# Parse ass / ass up args: optional -f/--force, -h/--help. Pwd-oriented (no repo name).\n"
        "# Sets _ASS_PARSE_FORCE (0|1).\n"
        "_ass_parse_args() {\n"
        "  _ASS_PARSE_FORCE=0\n"
        "  _ASS_PARSE_HELP=0\n",
    )
    body = re.sub(
        r"      \*\)\n"
        r'        if \[\[ -n "\$_ASS_PARSE_REPO" \]\]; then\n'
        r'          echo "ass: unexpected argument: \$1 \(try: [^"]*\)" >&2\n'
        r"          return 1\n"
        r"        fi\n"
        r'        _ASS_PARSE_REPO="\$1"\n',
        '      *)\n'
        '        _ass_err "ass: unexpected argument: $1 (pwd-oriented -- cd to the repo first)"\n'
        "        return 1\n",
        body,
        count=1,
    )
    body = body.replace(
        '_ass_resolve_sync_target "$_ASS_PARSE_REPO"',
        '_ass_resolve_sync_target ""',
    )
    body = body.replace("nutup || return 1", "ass_up || return 1")
    body = body.replace('_ass_parse_args "${_ass_argv[@]}" "$@"', '_ass_parse_args "${_ass_argv[@]}"')
    body = body.replace('echo "nutup: ${sync_target} -> origin main"', '_ass_info "ass up: ${sync_target} -> origin main"')
    body = body.replace('(try: nut --help)', '(try: ass --help)')
    body = body.replace('(try: nut <name>)', '(pwd-oriented -- cd to the repo first)')

    ASS_NEW = r'''
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

'''
    for dropit_anchor in (
        "  _ass_info \"dropit: review + commit in the agentstartstack clone, then ass.\"\n}\n\n# ass up trim",
        "  echo \"dropit: review + commit in the agentstartstack clone, then ass.\"\n}\n\n# ass up trim",
    ):
        if dropit_anchor in body:
            body = body.replace(
                dropit_anchor,
                dropit_anchor.replace(
                    "}\n\n# ass up trim",
                    "}\n\n" + ASS_NEW + "# ass up trim",
                    1,
                ),
                1,
            )
            break

    # Inject reconcile block before _ass_push
    body = body.replace(
        "_ass_push() {",
        ASS_INJECT + "\n_ass_push() {",
        1,
    )

    # Canonical WIP + preflight in _ass_push after best_dir selected
    body = body.replace(
        "  _ass_print_handoff_report",
        "  _ass_canonical_move_wip_to_clone \"$sync_target\" \"$best_dir\" || return 1\n"
        "  _ass_handoff_preflight \"$best_dir\" \"$sync_target\" || return 1\n\n"
        "  _ass_print_handoff_report",
        1,
    )

    # ass() / ass_up() help (pwd-oriented CLI)
    body = body.replace(
        "nut -- Newest commit Until Transferred",
        "ass -- AgentStartStack handoff (local-sync)",
    )
    body = body.replace(
        """  nut                 infer repo from pwd
  nut <name>          e.g. nut printstack, nut iotstack, nut wrtstack
  nut -f              only session clones initialized after the last ass
  nutup               local-sync, then git push origin main
  nutup -f            as nut -f, then push
  nutup <name>        local-sync for <name>, then push
  ass_up_all           nutup agentstartstack, refresh .agentstartstack submodules""",
        """  ass                 pwd-oriented handoff (cd to canonical or session clone)
  ass -f              only session clones initialized after the last ass
  ass up              local-sync, then git push origin main
  ass up -f           as ass -f, then push
  ass up trim         consolidate and prune stale session clones
  ass up --all        ass up agentstartstack, refresh consumer submodules
  ass dropit <src>    copy generic work into agentstartstack session clone""",
    )
    body = body.replace(
        "nutup -- local-sync with canonical local repo, then git push origin main",
        "ass up -- local-sync with canonical local repo, then git push origin main",
    )
    body = body.replace(
        """  nutup               infer repo from pwd
  nutup <name>        e.g. nutup printstack, nutup wrtstack
  nutup -f            only session clones initialized after the last ass, then push""",
        """  ass up              pwd-oriented (cd to canonical or session clone)
  ass up -f           only session clones initialized after the last ass, then push""",
    )
    body = body.replace("-f, --force  See nut --help.", "-f, --force  See ass --help.")
    body = body.replace("after the previous nut so", "after the previous ass so")
    body = body.replace(
        "ass_up_all -- local-sync and push agentstartstack",
        "ass up --all -- local-sync and push agentstartstack",
    )
    body = body.replace(
        """  ass_up_all
  ass_up_all --help""",
        """  ass up --all
  ass up --all --help""",
    )

    # Global flags on ass()
    if "_as_cli_parse_global_flags" not in body.split("ass()\n")[1][:400]:
        body = body.replace(
            "ass()\n{\n  _ass_parse_args",
            "ass()\n{\n  local -a _ass_argv\n  _as_cli_parse_global_flags _ass_argv \"$@\" || return 1\n  _ass_parse_args \"${_ass_argv[@]}\"",
            1,
        )
        body = body.replace(
            "ass_up()\n{\n  if [[ \"${1:-}\" == \"trim\" ]]; then",
            "ass_up()\n{\n  local -a _ass_argv\n  _as_cli_parse_global_flags _ass_argv \"$@\" || return 1\n  set -- \"${_ass_argv[@]}\"\n  if [[ \"${1:-}\" == \"trim\" ]]; then",
            1,
        )

    return header + body


ASS_SH = r'''#!/usr/bin/env bash
# ass.sh -- human-side git handoff CLI
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ass-aliases.sh
source "${SCRIPT_DIR}/lib/ass-aliases.sh"

_ass_cli_usage() {
  cat <<'EOF'
ass.sh -- AgentStartStack handoff (human-side git handoff)

Pwd-oriented: cd to the canonical repo or a session clone, then run a command.
After install-shell-aliases.sh, only a thin ass() wrapper is installed.

  ass.sh [-f]                     local-sync handoff (ass)
  ass.sh new --grok|--claude      create + align a session clone (canonical pwd)
  ass.sh drop                     archive all session clones except #1
  ass.sh drop <n>                 archive and remove session clone #n
  ass.sh up [-f]                  local-sync, then git push origin main
  ass.sh up trim [options]        consolidate and prune stale session clones
  ass.sh up --all                 ass up agentstartstack, refresh consumer submodules
  ass.sh drop <src> [dest]        copy generic work into agentstartstack session clone

Global flags: -v, -q, --timestamp, --log-id=ID, --create-log (see docs/cli.md)
EOF
}

_ass_cli_subcommand_help() {
  local sub="${1:-}"
  case "$sub" in
    new)    ass_new --help ;;
    drop)   ass_drop --help ;;
    up)     ass_up --help ;;
    trim)   ass_up_trim --help ;;
    all)    ass_up_all --help ;;
    ""|handoff|ass) ass --help ;;
    *)
      printf '[ERR]  ass.sh: unknown help topic: %s\n' "$sub" >&2
      return 1
      ;;
  esac
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    -h|--help|help)
      if [[ -n "${2:-}" ]]; then
        if [[ "${2:-}" == up && "${3:-}" == trim ]]; then
          _ass_cli_subcommand_help trim
        elif [[ "${2:-}" == up && "${3:-}" == --all ]]; then
          _ass_cli_subcommand_help all
        else
          _ass_cli_subcommand_help "${2}"
        fi
      else
        _ass_cli_usage
      fi
      ;;
    new) shift; ass_new "$@" ;;
    drop)  shift; ass_drop "$@" ;;
    up)
      shift
      if [[ "${1:-}" == trim ]]; then
        shift; ass_up_trim "$@"
      elif [[ "${1:-}" == --all ]]; then
        shift; ass_up_all "$@"
      else
        ass_up "$@"
      fi
      ;;

    *) ass "$@" ;;
  esac
}

main "$@"
'''


INSTALLER_BEGIN = "# >>> agentstartstack ass aliases >>>"
INSTALLER_END = "# <<< agentstartstack ass aliases <<<"


def patch_install_shell_aliases() -> None:
    src = REPO / "scripts/install-shell-aliases.sh"
    text = src.read_text(encoding="utf-8")
    text = text.replace("nut/nutup shell aliases", "ass shell alias (thin wrapper)")
    text = text.replace("nut-aliases.sh", "ass.sh")
    text = text.replace("nut aliases", "ass aliases")
    text = text.replace("nut/nutup/dropit", "ass")
    text = text.replace(
        'BEGIN_MARK="# >>> agentstartstack nut aliases >>>"',
        f'BEGIN_MARK="{INSTALLER_BEGIN}"',
    )
    text = text.replace(
        'END_MARK="# <<< agentstartstack nut aliases <<<"',
        f'END_MARK="{INSTALLER_END}"',
    )
    text = text.replace(
        'SRC="${SCRIPT_DIR}/lib/nut-aliases.sh"',
        'ASS_CLI="${SCRIPT_DIR}/ass.sh"',
    )
    text = text.replace("resolve_stable_src", "resolve_ass_cli")
    text = text.replace("STABLE_SRC", "ASS_CLI_PATH")
    text = text.replace("nut-aliases", "ass-cli")
    # Managed block: thin ass() wrapper only
    old_block = '[ -f "%s" ] && . "%s"'
    if old_block % ("$STABLE_SRC", "$STABLE_SRC") in text:
        text = text.replace(
            old_block % ("$STABLE_SRC", "$STABLE_SRC"),
            ': "${AGENTSTARTSTACK_ASS_CLI:=ASS_CLI_PLACEHOLDER}"\n'
            'ass() { bash "${AGENTSTARTSTACK_ASS_CLI}" "$@"; }',
        )
    text = text.replace("ASS_CLI_PLACEHOLDER", '"${SCRIPT_DIR}/ass.sh"')
    src.write_text(text, encoding="utf-8")


def patch_workflow_hard_rules() -> None:
    for wf in (REPO / "agentstartstack/workflow.md", REPO / "docs/workflow.md"):
        if not wf.is_file():
            continue
        text = wf.read_text(encoding="utf-8")
        if "HARD RULES" in text:
            continue
        rules = '''## HARD RULES

These rules are non-negotiable for humans and agents working with agentstartstack.

1. **Never hard-reset canonical toward a session clone.** Canonical is authoritative for
   published history. Session clones align *to* canonical via `init_*_session.sh`, not the
   reverse. If canonical and a session clone diverge, use `ass` handoff (session clone ->
   canonical), never `git reset --hard` on canonical to match a session clone.

2. **All session-clone work SHALL be committed automatically.** `init_*_session.sh` runs
   `auto-commit-session-work.sh` after align so agent edits are never left only in the
   working tree (where a mistaken hard-reset would destroy them).

'''
        text = text.replace("## Canonical paths\n", rules + "## Canonical paths\n")
        text = text.replace("nut", "ass")
        text = text.replace("agentstartstack/", "docs/")
        wf.write_text(text, encoding="utf-8")


def patch_init_scripts() -> None:
    for name, agent in (("init_grok_session.sh", "grok"), ("init_claude_session.sh", "claude")):
        path = REPO / "scripts" / name
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8")
        text = text.replace("nut/nutup", "ass")
        text = text.replace("nut ", "ass ")
        text = text.replace("nut.md", "ass.md")
        text = text.replace("agentstartstack/", "docs/")
        text = text.replace("lib/nut-aliases.sh", "ass.sh via install-shell-aliases.sh")
        if "agentstartstack-session-agent" not in text:
            text = text.replace(
                'date +%s > "${REPO_ROOT}/.git/agentstartstack-session-init"',
                f'date +%s > "${{REPO_ROOT}}/.git/agentstartstack-session-init"\n'
                f'printf \'%s\\n\' {agent} > "${{REPO_ROOT}}/.git/agentstartstack-session-agent"',
            )
        if "auto-commit-session-work.sh" not in text:
            text = text.replace(
                '"${SCRIPT_DIR}/install-shell-aliases.sh"',
                '"${SCRIPT_DIR}/auto-commit-session-work.sh" "$REPO_ROOT"\n'
                '"${SCRIPT_DIR}/install-shell-aliases.sh"',
            )
        path.write_text(text, encoding="utf-8")


def chmod_scripts() -> None:
    for rel in (
        "scripts/ass.sh",
        "scripts/ass-stash-compat-check.sh",
        "scripts/init_agent_session.sh",
        "scripts/auto-commit-session-work.sh",
        "scripts/commit-ass-migration.sh",
    ):
        p = REPO / rel
        if p.is_file():
            p.chmod(0o755)


def commit_if_dirty(msg: str, *paths: str) -> None:
    git("add", *paths)
    r = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=REPO)
    if r.returncode != 0:
        git("commit", "-m", msg)


def main() -> int:
    os.chdir(REPO)

    # 1. cli-log.sh (already on disk; ensure present)
    cli = extract_from_transcript("cli-log.sh")
    if cli:
        cli = cli.replace("nut-aliases.sh", "ass-aliases.sh")
        cli = cli.replace("agentstartstack/", "docs/")
        write(REPO / "scripts/lib/cli-log.sh", cli)
    commit_if_dirty("Add shared cli-log.sh for ass CLI output conventions", "scripts/lib/cli-log.sh")

    # 2. ass-aliases from nut-aliases
    nut = (REPO / "scripts/lib/nut-aliases.sh").read_text(encoding="utf-8")
    ass_aliases = transform_nut_to_ass(nut)
    write(REPO / "scripts/lib/ass-aliases.sh", ass_aliases)
    commit_if_dirty(
        "Add ass-aliases.sh: handoff, reconcile, canonical WIP, stash agent review",
        "scripts/lib/ass-aliases.sh",
    )

    # 3. ass.sh + helpers
    if not (REPO / "scripts/ass.sh").is_file():
        write(REPO / "scripts/ass.sh", ASS_SH)
    for name in ("init_agent_session.sh", "ass-stash-compat-check.sh", "auto-commit-session-work.sh"):
        content = extract_from_transcript(name)
        if content and not (REPO / "scripts" / name).is_file():
            write(REPO / "scripts" / name, content)
    chmod_scripts()
    commit_if_dirty(
        "Add ass.sh router, init_agent_session, stash compat check, auto-commit hook",
        "scripts/ass.sh",
        "scripts/init_agent_session.sh",
        "scripts/ass-stash-compat-check.sh",
        "scripts/auto-commit-session-work.sh",
        "scripts/commit-ass-migration.sh",
    )

    # 4. installer + init scripts
    patch_install_shell_aliases()
    patch_init_scripts()
    commit_if_dirty(
        "Install thin ass() wrapper; stamp agent kind; wire auto-commit on init",
        "scripts/install-shell-aliases.sh",
        "scripts/init_grok_session.sh",
        "scripts/init_claude_session.sh",
    )

    # 5. docs rename
    if (REPO / "agentstartstack").is_dir() and not (REPO / "docs").exists():
        git("mv", "agentstartstack", "docs")
    if (REPO / "docs/nut.md").is_file() and not (REPO / "docs/ass.md").is_file():
        git("mv", "docs/nut.md", "docs/ass.md")
    patch_workflow_hard_rules()
    # Cross-ref nut -> ass in docs
    docs = REPO / "docs"
    if docs.is_dir():
        for md in docs.glob("*.md"):
            t = md.read_text(encoding="utf-8")
            t2 = t.replace("nut.md", "ass.md").replace("`nut`", "`ass`").replace("nutup", "ass up")
            t2 = t2.replace("nutupyall", "ass up --all").replace("agentstartstack/", "docs/")
            if t2 != t:
                md.write_text(t2, encoding="utf-8")
    commit_if_dirty(
        "Rename agentstartstack/ to docs/; nut.md -> ass.md; add HARD RULES",
        "docs",
    )

    # 6. agentstartstack-config docs paths
    cfg = REPO / "scripts/lib/agentstartstack-config.sh"
    if cfg.is_file():
        t = cfg.read_text(encoding="utf-8")
        t = t.replace("nut's clone", "ass's clone")
        t = t.replace("nutupyall", "ass up --all")
        if "docs/" not in t.split("GENERIC_GUIDANCE_DIR")[1][:400]:
            t = t.replace(
                '  elif [[ -d "${root}/agentstartstack" ]]; then\n'
                '    GENERIC_GUIDANCE_DIR="agentstartstack"',
                '  elif [[ -d "${root}/docs" ]]; then\n'
                '    GENERIC_GUIDANCE_DIR="docs"\n'
                '  elif [[ -d "${root}/agentstartstack" ]]; then\n'
                '    GENERIC_GUIDANCE_DIR="agentstartstack"',
            )
        cfg.write_text(t, encoding="utf-8")
        commit_if_dirty("Resolve docs/ guidance path in agentstartstack-config.sh", str(cfg))

    print("Restore complete. Run: scripts/install-shell-aliases.sh && source ~/.bashrc")
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--aliases-only":
        os.chdir(REPO)
        nut = (REPO / "scripts/lib/nut-aliases.sh").read_text(encoding="utf-8")
        write(REPO / "scripts/lib/ass-aliases.sh", transform_nut_to_ass(nut))
        print("Wrote scripts/lib/ass-aliases.sh")
        sys.exit(0)
    sys.exit(main())