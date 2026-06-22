# agentstartstack (generic guidance)

Generic agent guidance shared across mini-projects via the `.agentstartstack` git submodule.

## How host projects use this

| Location | Content |
|----------|---------|
| `.agentstartstack/agentstartstack/` | **This directory** -- workflow, nut, conventions, security, etc. |
| `agentstartstack/` (project root) | Project-specific topics: CLI, architecture, gotchas, devices |

Agents load 1-3 files per task from **both** trees. Start with `workflow.md` for any git or session question.

## Session startup (Grok / Claude clone)

1. **Session sync** -- host project's `scripts/init_grok_session.sh` or `scripts/init_claude_session.sh` (see `workflow.md`)
2. Read the host project's `CLAUDE.md` index; load 1-3 topic files relevant to the task
3. Do not load all files unless doing a broad audit

## Publish (end of session)

1. Commit in the session clone
2. **Handoff** -- human runs `nut` (or `nutup`); see `nut.md`

## Suggested load patterns

| Task type | Files |
|-----------|-------|
| New project / submodule wiring | `submodule-integration.md`, `workflow.md` |
| Git / session clones / handoff | `workflow.md`, `nut.md` |
| New shell script | `conventions.md`, `code-quality.md`, `implementation.md` |
| Secrets / env files | `security.md`, `conventions.md` |
| Cursor terminal / copy-paste | `terminal.md` |
| CI / commit hygiene | `workflow.md`, `code-quality.md`, `testing.md` |
| Human local-sync handoff | `nut.md`, `workflow.md` |

Project-specific tasks (flash, build, provision, etc.) -- load from the host project's `agentstartstack/` per its `CLAUDE.md` index.

## Maintenance

- Generic changes: edit here, commit in `.agentstartstack` submodule, bump in host projects.
- Project changes: edit host `agentstartstack/` only.
- New generic topic file: update `.agentstartstack/CLAUDE.md` index and host project `CLAUDE.md` if agents should load it by default.