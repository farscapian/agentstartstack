# agentstartstack -- AI Development Notes (index)

Shared agent guidance template. **Load topic files from `docs/` instead of reading this index repeatedly.**

Host projects that include this repo as a submodule should use their own root `CLAUDE.md` as the primary index (generic + project-specific topics). This file documents the template repo itself.

**Template repo sessions:** canonical has no `.agentstartstack.env` (host projects only). ass does not create worktrees -- grok/claude create their own under `~/.grok/worktrees` / `~/.claude/worktrees`. Make one ass-aware with `ass adopt <path>` (writes `.agentstartstack.env`, runs init); `ass discover` lists agent worktrees not yet adopted. Do not run `init_*_session.sh` on canonical directly.

## Quick rules

- **FIRST, before any edit:** an agent's first order of business after reading this index is to set up its own session worktree and work there -- never edit canonical. ass does not create worktrees; grok/claude create their own under `~/.grok/worktrees` / `~/.claude/worktrees`, then `ass adopt <path>` (or `ass discover --adopt`) makes it ass-aware and aligns it. Confirm you are in that worktree before your first edit. (See `docs/workflow.md`.)
- Branding: always lowercase `agentstartstack`
- Text: ASCII-only in docs, logs, help, and code comments
- Agents work in session clones, NOT in the canonical local repo (see `docs/workflow.md`)
- New Grok session: run host project's `scripts/init_grok_session.sh` (wraps `agentstartstack/scripts/`)
- New Claude Code session: run host project's `scripts/init_claude_session.sh`
- After changes: commit in session clone; human runs `ass sync` then `git push origin main` (or `ass up`). NEVER `git push origin` from agents (see `docs/ass.md`)

## Topic index

| File | Load when |
|------|-----------|
| [docs/submodule-integration.md](docs/submodule-integration.md) | Wiring this repo into a host project |
| [docs/workflow.md](docs/workflow.md) | Repos, agent session clones, git sync, commit policy |
| [docs/ass.md](docs/ass.md) | `ass` / `ass up` -- AgentStartStack handoff CLI |
| [docs/cli-help.md](docs/cli-help.md) | `ass` help menu files (`docs/help/*.txt`) |
| [docs/cli-conventions.md](docs/cli-conventions.md) | Requirements for a host project that ships its own CLI |
| [docs/conventions.md](docs/conventions.md) | Naming, ASCII-only text, script output tags |
| [docs/terminal.md](docs/terminal.md) | Copy/paste in Cursor/Codium integrated terminal |
| [docs/security.md](docs/security.md) | Never print secrets; env file hygiene |
| [docs/code-quality.md](docs/code-quality.md) | shellcheck rules and git hooks |
| [docs/implementation.md](docs/implementation.md) | Common shell patterns (prompts, traps, env loading) |
| [docs/testing.md](docs/testing.md) | Pre-handoff validation checklist (generic) |

Full catalog: [docs/README.md](docs/README.md).