# ass CLI help menus

How `ass` structures terminal help (iotstack-style). Help text lives in
**external files** under `docs/help/`; shell code only routes to the right file.

## Design goals

1. **Main menu lists direct subcommands only** -- no flags, no nested verbs.
2. **Each command owns its help file** -- options, subcommands, examples, and
   cross-links stay out of the main menu.
3. **Nested subcommands get their own files** -- e.g. `ass sync all` and
   `ass up trim` are not summarized on the main menu; their help files describe
   them fully.
4. **Single source of truth** -- edit the `.txt` file, not a heredoc in shell.

## Help file layout

| File | Shown by |
|------|----------|
| `docs/help/ass.txt` | `ass`, `ass help` |
| `docs/help/ass-sync.txt` | `ass sync help`, `ass help sync` |
| `docs/help/ass-sync-all.txt` | `ass sync all help`, `ass help sync all` |
| `docs/help/ass-adopt.txt` | `ass adopt help`, `ass help adopt` |
| `docs/help/ass-discover.txt` | `ass discover help`, `ass help discover` |
| `docs/help/ass-list.txt` | `ass list help`, `ass help list` |
| `docs/help/ass-status.txt` | `ass status help`, `ass help status` |
| `docs/help/ass-info.txt` | `ass info help`, `ass help info` |
| `docs/help/ass-drop.txt` | `ass drop help`, `ass help drop` (collapse all, clone #n, upstream copy) |
| `docs/help/ass-up.txt` | `ass up help`, `ass help up` |
| `docs/help/ass-up-trim.txt` | `ass up trim help`, `ass help up trim` |
| `docs/help/ass-publish.txt` | `ass publish help`, `ass help publish` |

Naming convention (mirrors iotstack `iotstack-<command>.txt`):

- `ass.txt` -- top-level command catalog
- `ass-<command>.txt` -- one file per help topic the router can dispatch
- `ass-<parent>-<nested>.txt` -- nested subcommand help

## Invocation patterns

All of these are equivalent where noted:

```bash
ass                          # main menu (same as ass help)
ass help
ass help sync
ass sync help
ass sync -h                  # legacy; prefer ass sync help
ass help sync all
ass sync all help
ass help up trim
ass up trim help
ass publish help
```

Router entry points:

- `scripts/ass.sh` -- `help` / `-h` / `--help` as first arg; `ass help <topic>`
- `scripts/lib/ass-aliases.sh` -- each `ass_*` function checks `help` as first
  positional arg after global flags are stripped

Implementation helpers:

- `_ass_cat_help <filename>` -- print `docs/help/<filename>`
- `_ass_help_requested <arg>` -- true for `help`, `-h`, `--help`
- `ass_help_topic <command> [nested]` -- dispatch from `ass help ...`

## Main menu format (`ass.txt`)

Follow the iotstack main menu shape:

1. **Title line** -- `ass -- <one-line description>`
2. **Short intro** -- pwd-oriented usage note (one paragraph)
3. **`Commands:`** -- flat list of **direct** subcommands only (name + one-line blurb)
4. **Help pointer** -- `Use 'ass <command> help' for detailed help...`
5. **`Global Options:`** -- flags valid on any invocation
6. **Environment / paths** -- repo roots, session clone parents
7. **See also** -- links to markdown docs (not duplicated in terminal)

Do **not** put on the main menu:

- Per-command flags (`-f`, `--stashes`, `--dry-run`, ...)
- Nested subcommands (`sync all`, `up trim`)
- Usage examples for individual commands

## Subcommand help format (`ass-<command>.txt`)

Each subcommand file should include as needed:

1. **Title** -- `ass <command> -- <description>`
2. **Intro** -- what it does, where to run it from
3. **`Usage:`** -- invocation patterns
4. **`Subcommands:`** -- only direct children of this command
5. **`Options:`** / **`Arguments:`** -- flags and positional args
6. **`Help:`** -- list accepted help invocations for this topic
7. **`See also:`** -- other help files or `docs/*.md`

Nested files (`ass-sync-all.txt`, `ass-up-trim.txt`) follow the same sections but
omit unrelated subcommands.

**Multi-mode commands:** `ass-drop.txt` documents three behaviors in one file
(bare `ass drop`, `ass drop <n>`, `ass drop <src> [<dest>]`), selected at
runtime by argument shape. Do not split into separate top-level commands on the
main menu.

## Adding a new subcommand

1. Add a one-line entry under `Commands:` in `docs/help/ass.txt` (if top-level).
2. Create `docs/help/ass-<name>.txt` with full detail.
3. Add `ass_help_<name>()` in `scripts/lib/ass-aliases.sh` calling `_ass_cat_help`.
4. Wire `ass_help_topic` and the command function's `_ass_help_requested` check.
5. Update this file's table and `docs/help/README.md`.

## Relationship to markdown docs

| Layer | Purpose |
|-------|---------|
| `docs/help/*.txt` | Terminal help (`ass ... help`) -- concise, copy-paste ready |
| `docs/ass.md` | Workflow, semantics, human/agent policy |
| `docs/cli.md` | Log tags, global flags, log file paths |
| `docs/cli-help.md` | This file -- help menu structure and maintenance |

Optional future pattern (iotstack): `ass-<command>-detailed.txt` for deep dives
referenced from quick help but not printed by default.

## iotstack reference

agentstartstack copied this pattern from the iotstack repo:

- `docs/help/iotstack.txt` -- main menu, commands only
- `docs/help/iotstack-<command>.txt` -- per-command terminal help
- `iotstack <command> help` and `iotstack help <command>`
- Thin `help_*()` functions that `cat` external files

See iotstack `docs/help/README.md` for its command catalog.