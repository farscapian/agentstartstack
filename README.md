# agentstartstack

Shared AI agent guidance and workflow tooling for mini-projects. Add this repo as a **git submodule** so every new project starts with the same agent workflows, conventions, and session scripts.

## What you get

| Path | Purpose |
|------|---------|
| `ai-guidance/` | Generic agent docs: workflow, nut, conventions, security, terminal tips, etc. |
| `scripts/` | Parameterized `init_grok_session.sh`, `init_claude_session.sh`, git hooks |
| `templates/` | Stubs for wiring a new project (`.agentstartstack.env`, `CLAUDE.md`, project `ai-guidance/`) |

Each host project keeps **project-specific** guidance in its own top-level `ai-guidance/` directory. Agents read generic guidance from `agentstartstack/ai-guidance/` and project topics from `ai-guidance/`.

## Quick start (new project)

From an existing project repo (e.g. `wrtstack`):

```bash
# 1. Add submodule
git submodule add git@github.com:farscapian/agentstartstack.git agentstartstack

# 2. Run the wiring script (creates .agentstartstack.env, wrapper scripts, stubs)
./agentstartstack/scripts/add-to-project.sh

# 3. Edit .agentstartstack.env and CLAUDE.md for your project
# 4. Commit submodule + new files
git add agentstartstack .agentstartstack.env CLAUDE.md ai-guidance scripts
git commit -m "Add agentstartstack submodule and AI guidance"
```

Or clone with submodules:

```bash
git clone --recurse-submodules git@github.com:farscapian/<your-project>.git
```

## Agent session workflow (summary)

1. **Session sync** -- human runs `scripts/init_grok_session.sh` or `scripts/init_claude_session.sh` from the project (thin wrappers call into `agentstartstack/scripts/`).
2. **Work** -- agent edits only the session clone (`~/.grok/worktrees/...` or `~/.claude/worktrees/...`), never Sync.
3. **Handoff** -- human runs `nut` (or `nutup`) from `~/.bash_aliases`; agents never `git push origin`.

Full details: [`ai-guidance/workflow.md`](ai-guidance/workflow.md) and [`ai-guidance/nut.md`](ai-guidance/nut.md).

## Branding

Always lowercase **agentstartstack** in docs and messages (never Agent Start Stack / AgentStartStack).

## Maintenance

- Generic workflow changes belong here; bump the submodule in host projects when updated.
- Project-specific gotchas, CLI, architecture stay in each project's `ai-guidance/`.
- When `nut` behavior changes, update `ai-guidance/nut.md` and `~/.bash_aliases` on the management machine.