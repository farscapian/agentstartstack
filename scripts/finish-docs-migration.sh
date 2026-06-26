#!/usr/bin/env bash
# finish-docs-migration.sh -- complete agentstartstack/ -> docs/ when docs/ partially exists.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

transform_md() {
  local f="$1"
  sed -i \
    -e 's/nut\.md/ass.md/g' \
    -e 's/`nut`/`ass`/g' \
    -e 's/nutupyall/ass up --all/g' \
    -e 's/nutup trim/ass up trim/g' \
    -e 's/nutup/ass up/g' \
    -e 's/agentstartstack\/agentstartstack/docs/g' \
    -e 's/<repo>\/agentstartstack\//<repo>\/docs\//g' \
    -e 's/agentstartstack\/workflow/docs\/workflow/g' \
    -e 's/agentstartstack\/nut/docs\/ass/g' \
    -e 's/agentstartstack\//docs\//g' \
    -e 's/\bnut\b/ass/g' \
    "$f"
}

# Replace placeholder workflow with real content + transforms
if [[ -f agentstartstack/workflow.md ]]; then
  cp agentstartstack/workflow.md docs/workflow.md
  transform_md docs/workflow.md
  git add docs/workflow.md
fi

for f in README.md code-quality.md conventions.md implementation.md security.md \
         submodule-integration.md terminal.md testing.md; do
  if [[ -f "agentstartstack/$f" && ! -f "docs/$f" ]]; then
    git mv "agentstartstack/$f" "docs/$f"
    transform_md "docs/$f"
    git add "docs/$f"
  fi
done

if [[ -f agentstartstack/nut.md && ! -f docs/ass.md ]]; then
  git mv agentstartstack/nut.md docs/ass.md
  transform_md docs/ass.md
  git add docs/ass.md
fi

# Remove empty agentstartstack dir
if [[ -d agentstartstack ]] && [[ -z "$(ls -A agentstartstack 2>/dev/null)" ]]; then
  rmdir agentstartstack
  git add -u agentstartstack 2>/dev/null || true
elif [[ -d agentstartstack ]]; then
  echo "WARN: agentstartstack/ still has files:" >&2
  ls -la agentstartstack >&2
fi

# Restore scripts not yet committed
git add scripts/restore-ass-migration.py scripts/_generate_ass_aliases.sh scripts/gen-ass-aliases.sh 2>/dev/null || true

echo "Docs migration files staged."