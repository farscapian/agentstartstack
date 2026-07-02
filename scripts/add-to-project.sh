#!/usr/bin/env bash
# Wire agentstartstack into a host project: wrappers, config, stubs.
#
# Run from host project root after:
#   git submodule add git@github.com:farscapian/agentstartstack.git .agentstartstack
set -euo pipefail

info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

AGENTSTARTSTACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_ROOT="$(cd "${AGENTSTARTSTACK_ROOT}/.." && pwd)"
SUBMODULE_DIR=".agentstartstack"

if [[ ! -d "${HOST_ROOT}/.git" ]]; then
  echo "[ERR]  Host project root must be a git repo: ${HOST_ROOT}" >&2
  exit 1
fi

if [[ "$(readlink -f "$AGENTSTARTSTACK_ROOT")" != "$(readlink -f "${HOST_ROOT}/${SUBMODULE_DIR}")" ]]; then
  echo "[ERR]  Run from host project with agentstartstack submodule at ./${SUBMODULE_DIR}" >&2
  exit 1
fi

PROJECT_NAME="$(basename "$HOST_ROOT")"
DISPLAY_NAME="${DISPLAY_NAME:-$PROJECT_NAME}"
ORIGIN_URL="$(git -C "$HOST_ROOT" remote get-url origin 2>/dev/null || true)"
CANONICAL_LOCAL_REPO="${HOST_ROOT}"

write_wrapper() {
  local dest="$1"
  local target="$2"
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="\$(git rev-parse --show-toplevel 2>/dev/null || echo "${HOST_ROOT}")"
exec "\${ROOT}/${target}" "\$@"
EOF
  chmod +x "$dest"
}

# -- .agentstartstack.env -----------------------------------------------------

ENV_FILE="${HOST_ROOT}/.agentstartstack.env"
if [[ -f "$ENV_FILE" ]]; then
  warn ".agentstartstack.env already exists -- skipping"
else
  cat >"$ENV_FILE" <<EOF
# Agent session workflow identity (see .agentstartstack/agentstartstack/submodule-integration.md)
PROJECT_NAME=${PROJECT_NAME}
DISPLAY_NAME=${DISPLAY_NAME}
CANONICAL_LOCAL_REPO=${CANONICAL_LOCAL_REPO}
ORIGIN_URL=${ORIGIN_URL}

# Optional: pgrep pattern while CLI is running (blocks ass sync)
# ACTIVE_GUARD_PGREP=wrtstack (build|flash)
EOF
  ok "Created .agentstartstack.env"
fi

# -- Wrapper scripts ----------------------------------------------------------

write_wrapper "${HOST_ROOT}/scripts/init_grok_session.sh" "${SUBMODULE_DIR}/scripts/init_grok_session.sh"
write_wrapper "${HOST_ROOT}/scripts/init_claude_session.sh" "${SUBMODULE_DIR}/scripts/init_claude_session.sh"
write_wrapper "${HOST_ROOT}/scripts/install-githooks.sh" "${SUBMODULE_DIR}/scripts/install-githooks.sh"
write_wrapper "${HOST_ROOT}/scripts/shellcheck-staged.sh" "${SUBMODULE_DIR}/scripts/shellcheck-staged.sh"
ok "Created scripts/*.sh wrappers"

# -- .githooks ----------------------------------------------------------------

mkdir -p "${HOST_ROOT}/.githooks"
write_wrapper "${HOST_ROOT}/.githooks/pre-commit" "scripts/shellcheck-staged.sh"
ok "Created .githooks/pre-commit"

# -- Project docs stub --------------------------------------------------------
# Project-specific agent docs live in docs/, NOT a dir named agentstartstack/
# (that name collides with the template/submodule and confuses contributors).

GUIDANCE_DIR="${HOST_ROOT}/docs"
if [[ -d "$GUIDANCE_DIR" && -f "${GUIDANCE_DIR}/README.md" ]]; then
  warn "docs/ already exists -- skipping stub"
else
  mkdir -p "$GUIDANCE_DIR"
  cp "${AGENTSTARTSTACK_ROOT}/templates/docs-README.md" "${GUIDANCE_DIR}/README.md"
  ok "Created docs/README.md stub"
fi

# -- CLAUDE.md stub -----------------------------------------------------------

CLAUDE_FILE="${HOST_ROOT}/CLAUDE.md"
if [[ -f "$CLAUDE_FILE" ]]; then
  warn "CLAUDE.md already exists -- merge agentstartstack index manually"
  info "See templates/CLAUDE.md.project-stub for reference"
else
  sed \
    -e "s|@DISPLAY_NAME@|${DISPLAY_NAME}|g" \
    -e "s|@PROJECT_NAME@|${PROJECT_NAME}|g" \
    -e "s|@CANONICAL_LOCAL_REPO@|${CANONICAL_LOCAL_REPO}|g" \
    -e "s|@ORIGIN_URL@|${ORIGIN_URL}|g" \
    "${AGENTSTARTSTACK_ROOT}/templates/CLAUDE.md.project-stub" >"$CLAUDE_FILE"
  ok "Created CLAUDE.md"
fi

# -- Git receive config -------------------------------------------------------

if git -C "$HOST_ROOT" config --get receive.denyCurrentBranch >/dev/null 2>&1; then
  info "receive.denyCurrentBranch already set"
else
  git -C "$HOST_ROOT" config receive.denyCurrentBranch updateInstead
  ok "Set receive.denyCurrentBranch = updateInstead"
fi

echo ""
ok "agentstartstack wired into ${HOST_ROOT}"
info "Next: edit .agentstartstack.env, CLAUDE.md, and docs/"
info "Then: git add .agentstartstack .agentstartstack.env scripts .githooks docs CLAUDE.md"