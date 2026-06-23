# agentstartstack -- AI Development Notes (index)

Shared agent guidance template. **Load topic files from `agentstartstack/` instead of reading this index repeatedly.**

Host projects that include this repo as a submodule should use their own root `CLAUDE.md` as the primary index (generic + project-specific topics). This file documents the template repo itself.

**Do NOT run the init scripts (`scripts/init_claude_session.sh`, `scripts/init_grok_session.sh`) in this template repo.** They require a `.agentstartstack.env` at the repo root, which exists only in host projects -- the template intentionally has none, so the scripts will exit with `Missing .agentstartstack.env`. Init/session-align is a host-project step; when working on the template directly, skip it.

## Quick rules

- Branding: always lowercase `agentstartstack`
- Text: ASCII-only in docs, logs, help, and code comments
- Agents work in session clones, NOT in the canonical local repo (see `agentstartstack/workflow.md`)
- New Grok session: run host project's `scripts/init_grok_session.sh` (wraps `agentstartstack/scripts/`)
- New Claude Code session: run host project's `scripts/init_claude_session.sh`
- After changes: commit in session clone; human runs `nut` then `git push origin main` (or `nutup`). NEVER `git push origin` from agents (see `agentstartstack/nut.md`)

## Topic index

| File | Load when |
|------|-----------|
| [agentstartstack/submodule-integration.md](agentstartstack/submodule-integration.md) | Wiring this repo into a host project |
| [agentstartstack/workflow.md](agentstartstack/workflow.md) | Repos, agent session clones, git sync, commit policy |
| [agentstartstack/nut.md](agentstartstack/nut.md) | `nut` / `nutup` -- Newest commit Until Transferred |
| [agentstartstack/conventions.md](agentstartstack/conventions.md) | Naming, ASCII-only text, script output tags |
| [agentstartstack/terminal.md](agentstartstack/terminal.md) | Copy/paste in Cursor/Codium integrated terminal |
| [agentstartstack/security.md](agentstartstack/security.md) | Never print secrets; env file hygiene |
| [agentstartstack/code-quality.md](agentstartstack/code-quality.md) | shellcheck rules and git hooks |
| [agentstartstack/implementation.md](agentstartstack/implementation.md) | Common shell patterns (prompts, traps, env loading) |
| [agentstartstack/testing.md](agentstartstack/testing.md) | Pre-handoff validation checklist (generic) |

Full catalog: [agentstartstack/README.md](agentstartstack/README.md).