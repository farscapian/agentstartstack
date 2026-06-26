# ai-guidance (@DISPLAY_NAME@)

Project-specific agent guidance. Generic workflow, nut, conventions, and security live in the **agentstartstack** submodule:

- `.agentstartstack/agentstartstack/workflow.md`
- `.agentstartstack/agentstartstack/nut.md`
- `.agentstartstack/agentstartstack/conventions.md`

## Session startup

1. Run `scripts/init_grok_session.sh` or `scripts/init_claude_session.sh`
2. Read root `CLAUDE.md`; load 1-3 files from this directory for the task

## Add project topics here

| File | Load when |
|------|-----------|
| `architecture.md` | System design, components, data flow |
| `cli.md` | CLI commands, flags, logs |
| `gotchas.md` | Non-obvious behavior, timing, hardware quirks |
| `configuration.md` | Env files, config paths |
| `testing.md` | Hardware validation checklist (extends agentstartstack template) |

Append to the smallest applicable file. Update `CLAUDE.md` when adding a new file.