# Integrated terminal (Cursor / Codium / VS Code)

xterm.js-based integrated terminals make copy/paste harder than a standalone emulator. Agents and scripts should adapt.

## Copy/paste tips (human)

| Action | Integrated terminal | External terminal (recommended for long runs) |
|--------|---------------------|---------------------------------------------------|
| Copy | Select text, then `Ctrl+Shift+C` (not `Ctrl+C`) | Select + middle-click or `Ctrl+Shift+C` |
| Paste | `Ctrl+Shift+V` | `Ctrl+Shift+V` or middle-click |
| Newline in Grok prompt | `Alt+Enter` (`Shift+Enter` often submits in xterm.js) | `Shift+Enter` usually works |

**For long runs** (flash, build, provision): prefer an external terminal on the management machine. Use `--create-log` when the project CLI supports it and `tail -f` the session log -- plain text files are easy to copy from.

**Interactive prompts** (type yes to confirm): run in an external terminal or use `--force` flags when available.

## What makes copy/paste painful

- **OSC 8 hyperlinks** -- invisible escape bytes around "clickable" text; select/copy grabs garbage. Init scripts may use hyperlinks sparingly; prefer plain paths in agent-facing output.
- **`tee /dev/tty`** -- duplicates streams; integrated terminals handle `/dev/tty` poorly.
- **`--timestamp`** -- ISO prefix on every line breaks clean selection. Use only when tailing logs, not for copy-paste workflows.
- **ANSI colors** -- copy includes escape sequences. Prefer plain `[INFO]` lines or copy from session log files.
- **Agent terminal vs your Terminal panel** -- Cursor may run agent commands in a separate output stream. Copy commands from the chat panel when possible.

## Agent rules (Grok / Cursor / Claude Code)

- Put **copy-pasteable** commands and paths in the **chat response**, not only in terminal output.
- Prefer **short, plain** terminal output; avoid walls of text the user must select from the terminal.
- For diagnostics, point at **log files** rather than dumping log content into the terminal.
- Do not wrap paths in OSC hyperlinks or decorative Unicode.
- When the human needs to run something themselves, give the full command in a fenced code block in chat.

## Grok diagnostics

In the Grok TUI (not the IDE agent): run `/terminal-setup` to check clipboard routes and terminal detection.