# ass -- local-sync with canonical local repo

Human-side helper for the AI git workflow step **local-sync** (session clone -> canonical local repo via the `local-sync` remote). Agents commit in the session clone; the human runs `ass sync` to local-sync with the canonical local repo, reviews, then `git push origin main`. Bare `ass` shows the main help menu (iotstack-style).

**Canonical source:** [`scripts/ass.sh`](../scripts/ass.sh) and [`scripts/lib/ass-aliases.sh`](../scripts/lib/ass-aliases.sh) (tracked). Install the thin `ass()` wrapper with [`scripts/install-shell-aliases.sh`](../scripts/install-shell-aliases.sh) (both `init_*_session.sh` call it). Do **not** hand-edit the managed block in `~/.bash_aliases`.

## Why "ass"

Canonical backronym: **A**gent**S**tart**S**tack. Short, memorable, and deliberately cheeky.

Performs local-sync from the matching session clone (Claude or Grok) into the canonical local repo (`CANONICAL_LOCAL_REPO` in host `.agentstartstack.env`; defaults to the repo root). **Pwd-oriented:** `cd` to the canonical repo or a session clone, then run `ass sync` or `ass up` -- no repo-name argument.

**Canonical entry:** [`scripts/ass.sh`](../scripts/ass.sh) (tracked), with implementation in [`scripts/lib/ass-aliases.sh`](../scripts/lib/ass-aliases.sh). After `install-shell-aliases.sh`, your shell defines only a thin `ass()` wrapper that runs `bash scripts/ass.sh`.

Retired names: `s2s`, `land`, `s2ps`, `s2is`, `push`, `ass push`.

## Usage

```bash
ass                 # main help menu
ass help            # same as bare ass
ass sync            # local-sync handoff (pwd: canonical or session clone)
ass sync -f         # handoff only from a post-last-ass session clone
ass sync --stashes  # opt in: prompt to move canonical stashes to session clone
ass sync all        # align every session clone behind canonical
ass sync all --dry-run
ass adopt           # make an agent-created worktree ass-aware (write env + align)
ass adopt --grok    # force Grok (overrides path/marker inference)
ass adopt --claude  # force Claude Code
ass discover        # list agent worktrees for this repo + adopt status
ass discover --adopt  # adopt every unadopted worktree found
# ass does NOT create worktrees. grok/claude create their own under
# ~/.grok/worktrees and ~/.claude/worktrees; adopt/discover make them ass-aware.
ass drop            # archive all session clones except #1 (collapse into one)
ass drop <n>        # archive and remove session clone #n (see ass list)
ass drop <src>      # from consumer clone: copy generic work upstream
ass status          # ahead/behind origin/main for canonical and session clones
ass info <n>        # plain-language summary for session #n (from ass status)
ass list            # session clones for canonical pwd (by origin URL)
ass up              # ass sync, then git push origin main
ass up -f           # as ass sync -f, then push
ass up --stashes    # as ass sync --stashes, then push
ass up trim         # consolidate and prune stale session clones
ass publish         # ass up agentstartstack, then bump .agentstartstack in consumers
ass help            # main menu (direct subcommands only)
ass help sync       # detailed sync help (external file: docs/help/ass-sync.txt)
ass sync help       # same as ass help sync
ass sync all help
ass up help
ass up trim help
ass publish help
```

**`ass`** -- show the main help menu (direct subcommands only). Nested commands
(`sync all`, `up trim`) and per-command flags appear in their own
help files under `docs/help/`. Structure: [cli-help.md](cli-help.md).

Same pattern as iotstack (`iotstack <command> help`, files in `docs/help/`).

**`ass sync`** -- local-sync handoff: session clone -> canonical local repo. Human reviews before publishing.
Before handoff, **auto-syncs** any session clone behind canonical (no prompt), checks that
canonical is not behind `origin/main` (prompts to ff-only merge if it is), then picks the
session clone **farthest ahead of canonical** for handoff. Prints **pwd**, canonical, every
session clone (ahead/behind canonical), and which clone is selected.

**`ass up`** -- full human handoff: `ass sync`, then publish to `origin/main`. Agents never run `ass up` themselves.

**`-f` / `--force`** (on `ass sync` / `ass up`) -- among session clones for the repo, ignore any initialized **before** the last successful `ass` (tracked in the canonical repo as `.git/agentstartstack-ass-last`). Among the remaining clones, pick the one **farthest ahead of canonical** (tie: newest commit on `main`). Use when you started a fresh session after the previous ass and an older session clone still exists on disk.

**`--stashes`** -- opt in to canonical stash prompts during handoff. Works with `ass sync` and `ass up` (e.g. `ass sync --stashes`, `ass up --stashes`, `ass sync -f --stashes`).

**`ass publish`** -- template publish plus submodule refresh and bump. Run only from the agentstartstack canonical local repo (not a session clone, not another repo). It **first runs `ass discover --adopt`** (best-effort) so any agent-created worktree for this repo is adopted and its work rides along in the handoff. Then it local-syncs and pushes agentstartstack, then for every host canonical local repo whose `.gitmodules` references `farscapian/agentstartstack`:

- **No in-flight session clone** -- `git submodule update --remote` to see the delta it would adopt. If that delta is **action-free** (no `CONSUMER-ACTION:` in any producer commit), **auto-commit** the bump (`Bump .agentstartstack to <sha>`) and `git push origin main`. If the delta **carries a `CONSUMER-ACTION:`**, do **not** auto-commit (a blind pointer move would skip the actions) -- restore the submodule and report the consumer under "need agent (actions)" so an agent session reconciles it. That deferral is not left to chance: the next `init_*_session.sh` for the consumer detects the behind-remote action-bearing delta and **drops the `.agentstartstack-bump` watch file**, so its pre-commit reminder keeps resurfacing on every commit until the agent reconciles -- a persistent nudge, not a commit blocker (see [workflow.md](workflow.md#the-agentstartstack-bump-watch-file)). Unchanged consumers report "already current".
- **In-flight session clone(s)** -- uncommitted changes, or commits ahead of `local-sync/main`. Auto-committing the canonical bump would turn an in-flight clone's next `ass` into a non-fast-forward, so canonical is left untouched. Instead `ass publish` drops a gitignored **`.agentstartstack-bump` watch file** in every clone of that consumer (see [The .agentstartstack-bump watch file](workflow.md#the-agentstartstack-bump-watch-file)). The bump then **rides along**: the agent applies the submodule update on its next commit, and the bump reaches canonical via that agent's normal `ass` (a fast-forward). Other clones find canonical already current on their next align and just clear the flag.

The loop is per-consumer resilient: one failure (update, commit, or push) is logged and counted but does not abort the rest. A summary line reports `bumped / already current / flagged (in-flight) / need agent (actions) / trim-skipped / failed`.

**Shortcut:** `face down ass up` runs `ass up`, then `ass publish` (installed as a thin `face()` wrapper alongside `ass()` by `install-shell-aliases.sh`).

**Conventions**

| Item | Path |
|------|------|
| Canonical local repo | `CANONICAL_LOCAL_REPO` in `.agentstartstack.env` (defaults to the repo root) |
| Project-roots search | `AGENTSTARTSTACK_PROJECT_ROOTS` (colon-separated dirs holding `<name>/`) |
| Session clones | `~/.claude/worktrees/<name>/*` |
| | `~/.grok/worktrees/<name>/*` |

Session clones are matched by `origin` URL so repos cannot cross-contaminate. Handoff selects the clone **farthest ahead of canonical** (tie: newest commit on `main`). Session clones must never stay behind canonical -- `ass sync` auto-syncs them before handoff; use `ass sync all` to align every clone manually from canonical pwd. Canonical must not lag `origin/main`; `ass sync` warns and prompts to ff-only merge if it does.

## Guards

`ass sync` refuses to run while long-running tools are active on the canonical local repo (local-sync updates its working tree via `receive.denyCurrentBranch = updateInstead`):

| Repo | Blocks while |
|------|----------------|
| iotstack | `iotstack` / `iotstack.sh` running |
| printstack | `printstack` / `printstack.sh` running |
| wrtstack | `wrtstack (build|flash)` running |

To add a guard for a new project, extend `_ass_guard_active_sessions` in `scripts/lib/ass-aliases.sh` (see Source below).

## Workflow

1. Agent commits in session clone
2. Human reviews (optional): `ass sync` local-syncs with the canonical local repo
3. Human publishes: `git push origin main` from the canonical local repo, or combine: `ass up`

Agents never run `ass sync` or `ass up` unless the human explicitly asks.

See [workflow.md](workflow.md) for session align, agent clone paths, and full git policy.

## ass drop (upstream copy)

`ass drop <src> [<dest>]` -- from a **consumer** session clone, copy a generic feature or doc that belongs upstream in agentstartstack into agentstartstack's **latest session clone** (newest by commit, discovered by origin URL), so it can be committed there and flow upstream instead of being forked into the consumer. It implements the "originate upstream, don't fork" rule in [workflow.md](workflow.md).

- Distinct from `ass drop <n>` (archive session clone by index). Upstream mode is selected when the first argument is not a plain integer.
- Runs **only** from a consumer session clone (under `AGENT_SESSION_CLONE_PARENT`, with a `.agentstartstack` submodule). Refuses from a canonical repo or from agentstartstack's own clone.
- `<dest>` defaults to `<src>`'s path relative to the consumer clone root.
- Copy-only: it does not edit the consumer or commit in the agentstartstack clone. After it copies, review + commit in the agentstartstack clone and hand off with `ass sync`; if `<src>` was a fork created in the consumer, delete it there.
- Stamps `Dropit-Id: <session-guid>` on single-file drops (when missing) and appends to `.agentstartstack-dropits` in the consumer. See [Dropit + GUID](workflow.md#dropit--guid-traceable-upstream-handoff) in `workflow.md`.

## ass up trim (consolidate and prune)

`ass up trim` **consolidates and prunes** stale agent **session clones** for a consumer.
**Consolidate** rolls uncommitted work from older clones into the newest kept clone
(unless `--no-rollover`). **Prune** archives each stale clone as a verified `.tar.gz`,
then removes the source directory. Clones with commits not yet handed off to
canonical (unlanded) are **kept** and reported for cherry-pick; clones whose work
is already in canonical are prunable even before canonical is pushed to `origin`.

**HARD RULE:** session clones may only be removed after archive (see [workflow.md](workflow.md)
HARD RULES). `ass drop` and `ass up trim` are the **only** supported removal paths -- never
`rm -rf` a session clone by hand.

```bash
ass up trim                 # consumer inferred from pwd
ass up trim iotstack        # named consumer
ass up trim --all           # every configured consumer
ass up trim --dry-run       # plan only (never removes clones)
ass up trim --yes           # skip confirmation prompt
ass up trim --keep-latest 2 # keep two newest clones
```

Run from **canonical** or a **session clone**. Trim discovers every session clone for that
consumer, builds a **kept set** (`--keep-latest N` by mtime, plus the pwd clone when
applicable), and picks a **rollover target** (newest mtime in the kept set). Dirty work from
stale clones is rolled into the rollover target, then stale clones are archived and removed.
Before acting, it prints **pwd**, the **canonical** repo, each session clone (HEAD,
behind-canonical, dirty/unlanded), tarball destinations, and a **keep/prune plan**. Archives
and removals run only after `--yes` or an interactive `y` (not on `--dry-run`).

`ass publish` calls `ass up trim --yes` for each consumer as its final step (opt out with `ASS_PUBLISH_AUTOTRIM=0` in `.agentstartstack.env`; legacy `ASS_UP_ALL_AUTOTRIM=0` still honored). Set `AGENTSTARTSTACK_CLONE_ARCHIVE_DIR` to control where tarballs land (e.g. `~/.iotstack/archives/agent_clones`).

## ass list (session clones)

Lists every agent session clone for the project, discovered by **git origin URL**
(not folder name). Run from the **canonical** repo:

```bash
ass list
```

Shows agent kind (`grok` / `claude` from `.git/agentstartstack-session-agent`), `HEAD`,
commits **behind canonical**, and path (`~` shortens `$HOME`). Newest clone first;
the primary (newest) clone is marked **`1*`**, and the numeric index (`1`, `2`,
`3`, ...) is the argument for `ass drop` / `ass info`. Use `ass status` for
ahead/behind counts vs `origin/main`.

## ass sync all (align clones to canonical)

After you commit or `ass up` from the **canonical** repo, run `ass sync all` to pull
those commits into every session clone that is **behind canonical**. Run from the
canonical local repo:

```bash
ass sync all
ass sync all --dry-run    # plan only
```

For each clone discovered by origin URL:

- **Behind canonical** -- fast-forwards when the clone has no local commits, or
  rebases onto `local-sync/main` when it has diverged (agent commits not yet handed off).
- **Already aligned (0 behind)** -- skipped.
- **Dirty** -- auto-committed first (`auto-commit-session-work.sh`), then synced if still behind.

Use after publishing from canonical so active agent sessions pick up your changes
without re-running `init_*_session.sh` (which hard-resets). See also
[Re-align before committing](workflow.md#re-align-before-committing-mandatory) for
per-clone fast-forward during a session.

## ass status (agent session clones)

`ass status` lists **agent session clones only** (newest commit on `main` first;
ties — e.g. all clones aligned to the same canonical HEAD — break by newest session) — not canonical.
Each row shows ahead/behind vs **canonical/main**, then vs **`origin/main`**. Reference
SHAs appear in the table group-title row (`canonical (SHA) --> origin/main (SHA)`).
Session **#1** shows **`-->`** after **wip** (local-sync handoff to canonical). Run from
the canonical repo or any session clone (pwd-oriented).

`ass status` is **read-only** -- it never local-syncs. Run `ass sync` yourself when
you want to land agent work to canonical before reporting.

```bash
ass status
```

| Column | Meaning |
|--------|---------|
| **#** | `1*` = primary (newest) clone, the rollover target; `^` = rolls into #1 on trim/drop (`ass list` has numeric index for `ass drop`) |
| **agent** | `grok` / `claude` from `.git/agentstartstack-session-agent` |
| **wip** | Uncommitted work not yet in canonical: `-` (clean) or `dirty` |
| **-->** (after wip) | Session **#1** local-syncs to canonical (`ass sync` handoff); blank on other rows |
| **canonical** (group title) | First ahead/behind pair vs canonical/main |
| **ahead / behind** | Under **canonical** — vs canonical/main (ref in INFO line) |
| **origin/main** (group title) | Second ahead/behind pair vs `origin/main` (SHA in group-title row) |
| **ahead / behind** | Under **origin/main** — vs `origin/main` |
| **path** | Clone directory (`~` shortens `$HOME`) |

Example: a clone at **1 ahead** of canonical has one commit waiting for `ass` / `ass up`.

## ass info (session summary)

`ass info <n>` prints a short plain-language summary (1-2 paragraphs, no `[INFO]` tags) for
session clone **`n`** -- same index as the `#` column in `ass status`. Paragraph one covers
agent kind, init time, HEAD, sync position vs canonical and `origin/main`, and whether the
worktree is clean. Paragraph two appears when needed: commit subjects not yet in canonical,
and/or a dirty-work analysis (file counts, diff size, largest edited paths).

```bash
ass status
ass info 2
```

## Session titles (ass list)

`ass list` shows the **agent session title** for each clone in its own column:

- **grok** -- `session_summary` from the newest `~/.grok/sessions/<clone>/<uuid>/summary.json`.
- **claude** -- the latest `ai-title` from the Claude Code session that edited the clone
  (located by scanning `~/.claude/projects/*/*.jsonl` for the clone path; every
  the agent's claude session edits its worktree by absolute path, so the match is exact).

The full title is shown, word-wrapped onto continuation lines (indented under the
title column) when it is longer than the column. `ass status` does **not** show
the title -- use `ass list` for titles. Note the claude `ai-title` is generated by
Claude Code and refreshes only periodically, so it can lag the latest work.

## ass drop (archive session clones)

`ass drop` archives and removes session clones from the **canonical** repo. Same
archive-first HARD RULE as `ass up trim` -- if archiving or verification fails, the clone
is left in place. Dirty work rolls into another session clone when one exists; refuses
unlanded commits. **Refuses clones with an active grok or Claude session** (detected via
running `grok --resume` for that workspace, or a `claude` process with cwd in the clone) --
quit or close the agent session first.

Two additional safety guards (the cwd check above can miss a session run from
canonical, so these do not rely on it):

- **Primary / pwd guard:** `ass drop <n>` refuses to remove the **primary** clone
  (`#1`, the `1*` active rollover target) or the clone at your current **pwd**
  unless you pass **`--force`** (`-f`). Bare `ass drop` likewise skips the pwd clone
  without `--force`.
- **Last-session prompt:** dropping the **last remaining** agent session clone for
  the repo **always** prompts and proceeds only on an explicit `y` -- even with
  `--force` -- since no session clone would remain.

```bash
ass drop                  # archive all clones except #1 (collapse into one)
ass list                  # see # column
ass drop 2                # archive and remove clone #2
ass drop 1 --force        # drop the primary/pwd clone (override the guard)
```

Bare `ass drop` keeps session clone **#1** (newest commit on `main`) and archives every
other clone, rolling dirty work into #1. Prompts for confirmation when removing more than
one clone.

From a **consumer** session clone, `ass drop <src> [<dest>]` copies generic work upstream
into agentstartstack (see `docs/help/ass-drop.txt`).

## Source

The functions and aliases live in the tracked canonical file
[`scripts/lib/ass-aliases.sh`](../scripts/lib/ass-aliases.sh) -- `_ass_*` helpers and command
functions (`ass`, `ass_up`, `ass_up_trim`, `ass_publish`, `ass_adopt`,
`ass_discover`, `ass_status`, `ass_info`, `ass_list`, `ass_sync`, `ass_sync_all`,
`ass_drop`).
[`scripts/ass.sh`](../scripts/ass.sh) is the subcommand router.

Install / update the thin `ass()` wrapper in your shell:

```bash
scripts/install-shell-aliases.sh
source ~/.bashrc
```

The managed block in `~/.bash_aliases` defines only `ass() { bash "${AGENTSTARTSTACK_ASS_CLI}" "$@"; }`.
All logic stays in the repo. Never hand-edit the managed block.
