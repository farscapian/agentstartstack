# CLI output conventions

Shared logging for the **ass** handoff CLI (`scripts/ass.sh`, `scripts/lib/ass-aliases.sh`)
and for host-project entry scripts that source `scripts/lib/cli-log.sh`.

## Message tags

| Tag | Stream | When |
|-----|--------|------|
| `[INFO]` | stdout | Progress, context |
| `[OK]   ` | stdout | Success terminus |
| `[WARN]` | stderr | Recoverable issues |
| `[ERR]  ` | stderr | Failure (always shown, even in quiet mode) |
| `[DEBUG]` | stderr | Only with `-v` / `--verbose` |

Tags are colored on a TTY (iotstack-style): blue `[INFO]`, green `[OK]`, yellow
`[WARN]`, red `[ERR]`, dim `[DEBUG]`. Set `NO_COLOR=1` or `AS_CLI_COLOR=0` to
disable. Log files (`--log-id`) always store plain ASCII tags without escapes.

## Global flags (ass sync / ass up)

Parsed **before** subcommands and passed through nested calls where applicable:

| Flag | Effect |
|------|--------|
| `-v`, `--verbose` | Emit `[DEBUG]` lines |
| `-q`, `--quiet` | Suppress `[INFO]` / `[OK]` / `[WARN]` (not `[ERR]`) |
| `--timestamp` | Prefix each line with ISO-8601 timestamp |
| `--log-id=ID` | Mirror full output to `~/.agentstartstack/logs/ass-<ID>.log` (implies `-v` and `--timestamp`; incompatible with `-q`) |

Examples:

```bash
ass sync -v
ass up --timestamp
ass sync --log-id=handoff-20260626
bash scripts/ass.sh up trim --dry-run -v
```

## Log files

When `--log-id` is set, `cli-log.sh` opens:

`$AGENTSTARTSTACK_CLI_LOG_DIR/<AGENTSTARTSTACK_CLI_LOG_PREFIX>-<id>.log`

Defaults: `~/.agentstartstack/logs/ass-<id>.log` (prefix `ass` when sourced from ass-aliases).

## Implementation

- Library: [`scripts/lib/cli-log.sh`](../scripts/lib/cli-log.sh)
- Ass integration: [`scripts/lib/ass-aliases.sh`](../scripts/lib/ass-aliases.sh) (`_ass_info`, `_ass_ok`, …)
- Host projects: source `cli-log.sh` and use `_as_cli_*` directly, or wrap with project-specific prefixes

See also [conventions.md](conventions.md) (Script output).