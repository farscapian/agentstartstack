#!/usr/bin/env bash
# ass-stash-compat-check.sh -- session-clone agent review before moving a canonical stash.
#
# Exit codes:
#   0  agent advises YES (unique, compatible changes worth applying)
#   1  agent advises NO  (redundant or incompatible; reasoning on stdout)
#   2  agent unavailable or response unparseable
#
# Usage:
#   ass-stash-compat-check.sh --clone <session-clone> --canonical <canonical> --stash-ref stash@{N}

set -euo pipefail

err() { printf '[ERR]  %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ass-stash-compat-check.sh --clone PATH --canonical PATH --stash-ref stash@{N}

Ask the session-clone agent (Grok or Claude Code) whether a canonical git stash
should be applied into that clone. Read-only agent invocation.
EOF
}

clone=""
canonical=""
stash_ref=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clone) clone="$2"; shift 2 ;;
    --canonical) canonical="$2"; shift 2 ;;
    --stash-ref) stash_ref="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage >&2; exit 2 ;;
  esac
done

[[ -n "$clone" && -n "$canonical" && -n "$stash_ref" ]] || {
  err "Required: --clone, --canonical, --stash-ref"
  usage >&2
  exit 2
}

clone=$(readlink -f "$clone")
canonical=$(readlink -f "$canonical")

git -C "$canonical" stash show "$stash_ref" >/dev/null 2>&1 || {
  err "No such canonical stash: ${stash_ref}"
  exit 2
}

_assc_resolve_agent_kind() {
  local path="$1" marker kind parents base
  path=$(readlink -f "$path")

  marker="${path}/.git/agentstartstack-session-agent"
  if [[ -f "$marker" ]]; then
    kind=$(tr -d '[:space:]' < "$marker")
    if [[ "$kind" == grok || "$kind" == claude ]]; then
      printf '%s\n' "$kind"
      return 0
    fi
  fi

  parents="${AGENT_SESSION_CLONE_PARENT:-${HOME}/.claude/worktrees:${HOME}/.grok/worktrees}"
  local IFS=:
  for base in $parents; do
    [[ -n "$base" ]] || continue
    base=$(readlink -f "$base" 2>/dev/null || echo "$base")
    if [[ "$path" == "$base"/* ]]; then
      case "$base" in
        */.claude/worktrees|*claude*) printf 'claude'; return 0 ;;
        */.grok/worktrees|*grok*) printf 'grok'; return 0 ;;
      esac
    fi
  done

  if command -v grok >/dev/null 2>&1; then
    printf 'grok\n'
    return 0
  fi
  if command -v claude >/dev/null 2>&1; then
    printf 'claude\n'
    return 0
  fi
  return 1
}

_assc_truncate_text() {
  local text="$1" max="${2:-49152}"
  if [[ "${#text}" -le "$max" ]]; then
    printf '%s' "$text"
    return 0
  fi
  printf '%s\n\n[... truncated for agent prompt (%d bytes) ...]' \
    "${text:0:max}" "${#text}"
}

_assc_extract_agent_text() {
  local raw="$1"
  if command -v jq >/dev/null 2>&1; then
    local parsed
    parsed=$(printf '%s' "$raw" | jq -r '
      if type == "object" then
        .text // .result // .content[0].text // empty
      else empty end
    ' 2>/dev/null) || true
    if [[ -n "$parsed" ]]; then
      printf '%s' "$parsed"
      return 0
    fi
  fi
  printf '%s' "$raw"
}

_assc_parse_verdict() {
  local text="$1"
  local verdict="" reason=""

  if [[ "$text" =~ ASS_STASH_COMPAT:[[:space:]]*(YES|NO) ]]; then
    verdict="${BASH_REMATCH[1]}"
    reason="${text#*ASS_STASH_COMPAT:*}"
    reason="${reason#*[Yy][Ee][Ss]}"
    reason="${reason#*[Nn][Oo]}"
    reason="${reason//$'\r'/}"
    reason="${reason#"${reason%%[![:space:]]*}"}"
  elif [[ "$text" =~ ^[[:space:]]*(YES|NO)[[:space:]]*$ ]]; then
    verdict="${BASH_REMATCH[1]}"
  elif grep -qi '^ASS_STASH_COMPAT:[[:space:]]*YES' <<<"$text"; then
    verdict=YES
    reason=$(grep -vi '^ASS_STASH_COMPAT:' <<<"$text" || true)
  elif grep -qi '^ASS_STASH_COMPAT:[[:space:]]*NO' <<<"$text"; then
    verdict=NO
    reason=$(grep -vi '^ASS_STASH_COMPAT:' <<<"$text" || true)
  fi

  [[ -n "$verdict" ]] || return 1
  printf '%s\n' "$verdict"
  if [[ -n "${reason// }" ]]; then
    printf '%s' "$reason"
  else
    printf '%s' "$text"
  fi
}

_assc_invoke_grok() {
  local prompt="$1" workdir="$2"
  local raw text

  command -v grok >/dev/null 2>&1 || return 1

  raw=$(
    grok -p "$prompt" \
      --cwd "$workdir" \
      --output-format json \
      --max-turns 15 \
      --yolo \
      --tools "read_file,grep,list_dir,run_terminal_cmd" \
      --disallowed-tools "search_replace,write,web_search,web_fetch,Agent" \
      2>/dev/null
  ) || return 1

  text=$(_assc_extract_agent_text "$raw")
  [[ -n "${text// }" ]] || return 1
  printf '%s' "$text"
}

_assc_invoke_claude() {
  local prompt="$1" workdir="$2"
  local raw text cmd=()

  command -v claude >/dev/null 2>&1 || return 1

  cmd=(claude -p "$prompt" --cwd "$workdir" --output-format json --max-turns 15)
  if claude --help 2>&1 | grep -q -- '--disallowed-tools'; then
    cmd+=(--disallowed-tools "Edit,Write,NotebookEdit")
  fi

  raw=$("${cmd[@]}" 2>/dev/null) || return 1
  text=$(_assc_extract_agent_text "$raw")
  [[ -n "${text// }" ]] || return 1
  printf '%s' "$text"
}

_assc_invoke_agent() {
  local kind="$1" prompt="$2" workdir="$3"
  case "$kind" in
    grok) _assc_invoke_grok "$prompt" "$workdir" ;;
    claude) _assc_invoke_claude "$prompt" "$workdir" ;;
    *)
      _assc_invoke_grok "$prompt" "$workdir" \
        || _assc_invoke_claude "$prompt" "$workdir"
      ;;
  esac
}

agent_kind=$(_assc_resolve_agent_kind "$clone") || {
  err "Cannot resolve session-clone agent (grok/claude not in PATH)"
  exit 2
}

stash_line=$(git -C "$canonical" stash list 2>/dev/null | grep -F "${stash_ref}:" | head -1 || true)
stash_stat=$(git -C "$canonical" stash show --stat "$stash_ref" 2>/dev/null || true)
stash_patch=$(
  git -C "$canonical" stash show -p --include-untracked "$stash_ref" 2>/dev/null \
    || git -C "$canonical" stash show -p "$stash_ref" 2>/dev/null \
    || true
)
stash_patch=$(_assc_truncate_text "$stash_patch")

clone_head=$(git -C "$clone" log -1 --oneline 2>/dev/null || echo "(unknown)")
clone_log=$(git -C "$clone" log -15 --oneline 2>/dev/null || true)

prompt=$(cat <<EOF
You are reviewing whether a canonical-repo git stash should be applied into this session clone.

Answer YES only if the stash contains unique, conceptually compatible changes that are NOT already adequately represented in this session clone's git history.

Answer NO if:
- the functionality is already present in the clone's git history (duplicate/redundant), OR
- the changes conflict with or are incompatible with the clone's current direction.

You may inspect this repository with read-only git commands and file reads. Do not modify any files.

Reply format (strict):
Line 1: ASS_STASH_COMPAT: YES   or   ASS_STASH_COMPAT: NO
Line 2: blank
Line 3+: brief reasoning (2-6 sentences)

Session clone: ${clone}
HEAD: ${clone_head}

Recent session-clone history:
${clone_log}

Canonical stash: ${stash_ref}
${stash_line}

Stash stat:
${stash_stat}

Stash patch:
${stash_patch}
EOF
)

agent_text=$(_assc_invoke_agent "$agent_kind" "$prompt" "$clone") || {
  err "Session-clone agent (${agent_kind}) failed or returned empty output"
  exit 2
}

verdict=""
reason=""
if ! read -r verdict reason < <(_assc_parse_verdict "$agent_text"); then
  err "Session-clone agent (${agent_kind}) returned an unparseable verdict"
  printf '%s\n' "$agent_text" >&2
  exit 2
fi

case "$verdict" in
  YES) exit 0 ;;
  NO)
    if [[ -n "${reason// }" ]]; then
      printf '%s\n' "$reason"
    else
      printf '%s\n' "$agent_text"
    fi
    exit 1
    ;;
  *)
    err "Session-clone agent (${agent_kind}) returned an unparseable verdict"
    exit 2
    ;;
esac