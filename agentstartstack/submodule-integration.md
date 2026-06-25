# Submodule Integration

How to wire `agentstartstack` into a host project (e.g. `wrtstack`, `iotstack`, `printstack`).

## Layout after integration

```
<host-project>/
|--- .agentstartstack/             # git submodule (this repo)
|   `--- agentstartstack/          # generic guidance (this directory)
|--- agentstartstack/              # project-specific agent docs
|--- .agentstartstack.env          # project identity for init scripts
|--- CLAUDE.md                     # combined index (generic + project)
|--- scripts/
|   |--- init_grok_session.sh      # thin wrapper -> .agentstartstack
|   |--- init_claude_session.sh
|   |--- install-githooks.sh
|   `--- shellcheck-staged.sh
`--- .githooks/pre-commit
```

## Add to an existing project

```bash
cd ~/Sync/mini_projects/<project>

# Add submodule (first time)
git submodule add git@github.com:farscapian/agentstartstack.git .agentstartstack

# Wire wrappers and stubs
./.agentstartstack/scripts/add-to-project.sh

# Customize
$EDITOR .agentstartstack.env
$EDITOR CLAUDE.md
$EDITOR agentstartstack/README.md

git add .agentstartstack .agentstartstack.env CLAUDE.md agentstartstack scripts .githooks
git commit -m "Add agentstartstack submodule and AI guidance"
```

## `.agentstartstack.env`

Required variables (created from template by `add-to-project.sh`):

| Variable | Example | Purpose |
|----------|---------|---------|
| `PROJECT_NAME` | `wrtstack` | Directory name under `~/Sync/mini_projects/` and worktree parent `mini-projects-<name>` |
| `DISPLAY_NAME` | `wrtstack` | Lowercase branding in init script tips |
| `SYNC_REPO` | `~/Sync/mini_projects/wrtstack` | Canonical local repo path |
| `ORIGIN_URL` | `git@github.com:farscapian/wrtstack.git` | For clone instructions in init output |
| `ACTIVE_GUARD_PGREP` | `wrtstack (build\|flash)` | Optional regex for nut safety checks in agent tips |

## CLAUDE.md pattern

Host `CLAUDE.md` should:
1. State project purpose in a short intro
2. Link generic workflow: `.agentstartstack/agentstartstack/workflow.md`, `nut.md`
3. Index project-specific files under `agentstartstack/`
4. Repeat quick rules: session clones, never push origin, lowercase branding

See `templates/CLAUDE.md.project-stub` in this repo.

## Git receive configuration

On the canonical local repo (one-time per project):

```bash
cd ~/Sync/mini_projects/<project>
git config receive.denyCurrentBranch updateInstead
```

This lets `nut` local-sync from session clones directly into the canonical local repo working tree.

## Updating agentstartstack

```bash
cd ~/Sync/mini_projects/<project>
cd .agentstartstack && git pull origin main && cd ..
git add .agentstartstack
git commit -m "Bump agentstartstack submodule"
git push origin main
```

Re-run `./scripts/install-githooks.sh` in session clones after hook script changes.

## Migrating existing projects (iotstack, printstack)

These repos have inline `agentstartstack/` with mixed generic + project content. Migration path:

1. Add `.agentstartstack` submodule
2. Run `add-to-project.sh` (creates wrappers; keeps existing `agentstartstack/` for project docs)
3. Trim duplicated generic sections from project `agentstartstack/workflow.md` and `nut.md`; link to `.agentstartstack/agentstartstack/` instead
4. Update `CLAUDE.md` to index both trees

Optional: keep project `scripts/init_*.sh` as one-line wrappers for backward compatibility.

## nut guard for new projects

Add a case to `_nut_guard_active_sessions` in `~/.bash_aliases` (documented in `nut.md`). Use `PROJECT_NAME` / canonical local repo directory name for the case path.