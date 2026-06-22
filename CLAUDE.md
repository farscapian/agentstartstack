# agentstartstack -- AI Development Notes (index)

Shared agent guidance template. **Load topic files from `ai-guidance/` instead of reading this index repeatedly.**

Host projects that include this repo as a submodule should use their own root `CLAUDE.md` as the primary index (generic + project-specific topics). This file documents the template repo itself.

## Quick rules

- Branding: always lowercase `agentstartstack`
- Text: ASCII-only in docs, logs, help, and code comments
- Agents work in session clones, NOT in Sync (see `ai-guidance/workflow.md`)
- New Grok session: run host project's `scripts/init_grok_session.sh` (wraps `agentstartstack/scripts/`)
- New Claude Code session: run host project's `scripts/init_claude_session.sh`
- After changes: commit in session clone; human runs `nut` then `git push origin main` (or `nutup`). NEVER `git push origin` from agents (see `ai-guidance/nut.md`)

## Topic index

| File | Load when |
|------|-----------|
| [ai-guidance/submodule-integration.md](ai-guidance/submodule-integration.md) | Wiring this repo into a host project |
| [ai-guidance/workflow.md](ai-guidance/workflow.md) | Repos, agent session clones, git sync, commit policy |
| [ai-guidance/nut.md](ai-guidance/nut.md) | `nut` / `nutup` -- Newest commit Until Transferred |
| [ai-guidance/conventions.md](ai-guidance/conventions.md) | Naming, ASCII-only text, script output tags |
| [ai-guidance/terminal.md](ai-guidance/terminal.md) | Copy/paste in Cursor/Codium integrated terminal |
| [ai-guidance/security.md](ai-guidance/security.md) | Never print secrets; env file hygiene |
| [ai-guidance/code-quality.md](ai-guidance/code-quality.md) | shellcheck rules and git hooks |
| [ai-guidance/implementation.md](ai-guidance/implementation.md) | Common shell patterns (prompts, traps, env loading) |
| [ai-guidance/testing.md](ai-guidance/testing.md) | Pre-handoff validation checklist (generic) |

Full catalog: [ai-guidance/README.md](ai-guidance/README.md).