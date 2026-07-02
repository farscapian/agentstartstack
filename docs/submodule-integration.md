# Submodule Integration

How to wire `agentstartstack` into a host project (e.g. `wrtstack`, `iotstack`, `printstack`).

## Layout after integration

```
<host-project>/
|--- .docs/             # git submodule (this repo)
|   `--- docs/          # generic guidance (this directory)
|--- docs/                         # project-specific agent docs
|--- .agentstartstack.env          # project identity for init scripts
|--- .agentstartstack-action-seen  # CONSUMER-ACTION watermark (tracked; see workflow.md)
|--- CLAUDE.md                     # combined index (generic + project)
|--- scripts/
|   |--- init_grok_session.sh      # thin wrapper -> .agentstartstack
|   |--- init_claude_session.sh
|   |--- install-githooks.sh
|   `--- shellcheck-staged.sh
`--- .githooks/pre-commit
```

**Rule -- project docs live in `docs/`, not `docs/`.** A host project's own project-specific agent documentation SHALL live in `docs/` at the repo root (i.e. `CANONICAL_LOCAL_REPO/docs`). Do **not** name it `docs/`: that name belongs to the template and the `.agentstartstack` submodule, and reusing it for project docs confuses contributors about what is generic vs project-specific. During initialization the init scripts resolve project guidance to `docs/` (falling back to a legacy `docs/` only until a consumer migrates).

## Add to an existing project

```bash
cd /path/to/<project>   # wherever you cloned it

# Add submodule (first time)
git submodule add git@github.com:farscapian/agentstartstack.git .agentstartstack

# Wire wrappers and stubs
./.docs/scripts/add-to-project.sh

# Customize
$EDITOR .agentstartstack.env
$EDITOR CLAUDE.md
$EDITOR docs/README.md

git add .agentstartstack .agentstartstack.env CLAUDE.md docs scripts .githooks
git commit -m "Add agentstartstack submodule and AI guidance"
```

## `.agentstartstack.env`

Required variables (created from template by `add-to-project.sh`):

| Variable | Example | Purpose |
|----------|---------|---------|
| `PROJECT_NAME` | `wrtstack` | Repo directory name; used for `ass <name>` lookups and init messaging |
| `DISPLAY_NAME` | `wrtstack` | Lowercase branding in init script tips |
| `CANONICAL_LOCAL_REPO` | (defaults to repo root) | Canonical local repo path; set only if the checkout lives elsewhere |
| `ORIGIN_URL` | `git@github.com:farscapian/wrtstack.git` | For clone instructions in init output |
| `ACTIVE_GUARD_PGREP` | `wrtstack (build\|flash)` | Optional regex for ass safety checks in agent tips |

## CLAUDE.md pattern

Host `CLAUDE.md` should:
1. State project purpose in a short intro
2. Link generic workflow: `.docs/workflow.md`, `ass.md`
3. Index project-specific files under `docs/`
4. Repeat quick rules: session clones, never push origin, lowercase branding

See `templates/CLAUDE.md.project-stub` in this repo.

## Git receive configuration

On the canonical local repo (one-time per project):

```bash
cd /path/to/<project>   # wherever you cloned it
git config receive.denyCurrentBranch updateInstead
```

This lets `ass` local-sync from session clones directly into the canonical local repo working tree.

## Updating agentstartstack

```bash
cd /path/to/<project>   # wherever you cloned it
cd .agentstartstack && git pull origin main && cd ..
git add .agentstartstack
git commit -m "Bump agentstartstack submodule"
git push origin main
```

Re-run `./scripts/install-githooks.sh` in session clones after hook script changes.

## Migrating existing projects (iotstack, printstack)

These repos have an inline `docs/` dir mixing generic + project content -- and that name now collides with the convention. Migration path:

1. Add `.agentstartstack` submodule
2. Run `add-to-project.sh` (creates wrappers and a `docs/` stub)
3. Move project-specific content from the old `docs/` into `docs/`, dropping duplicated generic sections (link to `.docs/` instead); then remove the old `docs/` dir
4. Update `CLAUDE.md` to index both trees (`.docs/` generic, `docs/` project)

Optional: keep project `scripts/init_*.sh` as one-line wrappers for backward compatibility.

## ass guard for new projects

Add a case to `_ass_guard_active_sessions` in `~/.bash_aliases` (documented in `ass.md`). Use `PROJECT_NAME` / canonical local repo directory name for the case path.