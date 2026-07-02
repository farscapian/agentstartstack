# CLI conventions (host projects that ship a CLI)

Requirements for any repo that consumes agentstartstack **and** ships a shell CLI
(iotstack, printstack, wrtstack, ...). They are derived from the iotstack
reference implementation and from `ass` itself. The terminal help-file *layout*
lives in [cli-help.md](cli-help.md); this file covers the CLI's **structure,
output, flags, and behavior**. Load both when building or extending a project CLI.

Language: **SHALL** = required for a conforming CLI; **SHOULD** = strong default,
deviate only with reason. All CLI text stays ASCII-only (see [conventions.md](conventions.md)).

## 1. Single entrypoint, subcommand dispatch (SHALL)

- One executable `<project>.sh` with `set -euo pipefail`, invoked as a bare
  `<project>` command via an alias, symlink, or thin wrapper.
- Guard the entrypoint so it can be sourced for tests:
  `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`.
- `main()` normalizes global flags (see 4), then dispatches with
  `case "$command"` to a `cmd_<name>` function per subcommand.
- An unknown command SHALL fail and point at help:
  `err "Unknown command: <x>. Try '<project> help'"`. Same for unknown
  subcommands of a group (`<project> matter <x>`).

## 2. Help is data, not code (SHALL)

**The help-file layout, naming (`<project>-<command>.txt`), main-menu shape, and
per-command file sections are specified in [cli-help.md](cli-help.md) -- follow
that document; it is not restated here.** This section states only the behavioral
requirements a conforming CLI SHALL meet:

- Help text lives in external `docs/help/*.txt` files; `help_<cmd>()` functions
  only `cat` the matching file. Never embed help as heredocs in shell.
- Three equivalent access forms SHALL work:
  `<project>` / `<project> help` (top-level), `<project> <cmd> help`, and
  `<project> help <cmd>`. Every `cmd_<name>` checks `help` as its first arg and
  prints that command's file.
- Contextual/per-entity help is encouraged where the CLI has a primary noun
  (iotstack: `<project> help <role>`, `<project> <cmd> <role> help`).

## 3. Message helpers with tagged, gated output (SHALL)

- Define `err / ok / warn / info / debug` once, emitting the standard tags
  `[ERROR] / [OK] / [WARN] / [INFO] / [DEBUG]` (aligns with the agentstartstack
  `[OK]/[INFO]/[ERR]` output-tag convention in [conventions.md](conventions.md)).
- Define colors once (`RED/GRN/YLW/BLU/DIM/RST`) and disable them when stdout is
  not a tty or when a `--no-color`/`NO_COLOR` signal is present.
- `err` writes to **stderr** and `exit 1`. `debug` writes to stderr and is gated
  on verbose. `ok/warn/info/debug` are all suppressed under `--quiet`.

## 4. Global flags valid anywhere (SHALL)

- A global-argv parser SHALL accept global flags **before or after** the
  subcommand and rewrite the positional args (iotstack: `iotstack_parse_global_argv`
  -> `IOTSTACK_ARGV`). `<project> -v update x` and `<project> update x -v` behave
  identically.
- Standard global set: `-v/--verbose` and `-q/--quiet` (mutually exclusive),
  `--timestamp`, `--dry-run`, `--json`, and log flags (`--create-log` /
  `--log-id`, or a `LOG_TO_FILE` env toggle as `ass` uses).

## 5. Exit codes and actionable errors (SHALL)

- Fail non-zero (via `err`, which exits 1); succeed zero. Do not swallow errors.
- Every user-facing error SHALL name the fix, not just the fault:
  - bad input -> list the valid values (iotstack unknown-role lists roles and
    points to `<project> roles`);
  - a recoverable condition -> print a copy-paste remediation command (iotstack
    serial-port-in-use prints the exact `kill`/`screen` line);
  - a usage error -> reference the help file (`... (see: <project> <cmd> help)`).

## 6. Destructive or multi-target ops confirm (SHALL)

- Prompt before any irreversible action or one that affects more than one target;
  default **No** (`y/N`). Skip the prompt for a single, safe target.
- A `-f/--force` flag bypasses the prompt for scripted use. A CLI SHALL NOT take
  a destructive action with neither a confirmation nor `--force`.

## 7. Dry-run and machine output (SHOULD)

- `--dry-run` performs all computation and prints what *would* happen with **no
  side effects**.
- `--json` emits machine-readable output, guarded by a `command -v jq` check that
  errors clearly when jq is absent. Human table output stays the default.

## 8. Discover valid inputs, do not hardcode (SHOULD)

- Enumerate targets/roles/subjects from files or config at runtime rather than
  baking a fixed list into the script (iotstack discovers roles from `roles.conf`
  / `yamls/`). Keeps the CLI correct as the project grows and avoids the
  org/path hardcoding this repo is trying to shed.

## 9. Deprecations forward with a warning (SHOULD)

- Keep a renamed command working: `warn` that it is deprecated, name the
  replacement, then forward to it (iotstack `commission` -> `matter commission`).
  Remove only after a grace period.

## 10. Session logging (SHOULD)

- Long-running CLIs SHOULD support teeing console output to a per-command log
  (`--create-log` / `--log-id`, or `LOG_TO_FILE=1` like `ass`), implying
  `--timestamp`. Logs stay ASCII-clean (color auto-disabled when tee'd).

## 11. Introspection: list and stop running work (SHOULD)

- A CLI that launches long or parallel operations SHOULD offer a way to list
  running invocations and stop them (iotstack `ps` / `kill`).

## Reconciling an existing project CLI

When this guidance lands in a consumer, run the discovery helper from the
consumer repo root to get a concrete worklist -- it lists your CLI-related
project docs and root `CLAUDE.md` CLI pointers, then leaves the (judgement)
reconciliation to you. It edits nothing.

```bash
.agentstartstack/scripts/reconcile-cli-guidance.sh
```

Then: trim project-local CLI conventions now covered generically here, refactor
what remains under your `docs/` down to project-specific specifics only, and
update your `CLAUDE.md` CLI pointers. (This is the `CONSUMER-ACTION` that rides
the commit introducing this file.)

## Reference implementation

- **iotstack** -- `iotstack.sh` (entrypoint, `main()` dispatch, message helpers,
  global-argv parser) and `docs/help/*.txt` (help catalog). The fullest example.
- **ass** -- `scripts/ass.sh` + `scripts/lib/ass-aliases.sh` follow the
  help-file half and the `LOG_TO_FILE` logging pattern.

See also: [cli-help.md](cli-help.md) (help-file layout), [conventions.md](conventions.md)
(output tags, ASCII), [code-quality.md](code-quality.md) (shellcheck),
[implementation.md](implementation.md) (prompts, traps, env loading).
