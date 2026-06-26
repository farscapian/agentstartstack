# ass -- local-sync with canonical local repo

Human-side helper for the AI git workflow step **local-sync** (session clone -> canonical local repo via the `local-sync` remote). Agents commit in the session clone; the human runs `ass` to local-sync with the canonical local repo, reviews, then `git push origin main`.

**Canonical source:** [`scripts/ass.sh`](../scripts/ass.sh) and [`scripts/lib/ass-aliases.sh`](../scripts/lib/ass-aliases.sh) (tracked). Install the thin `ass()` wrapper with [`scripts/install-shell-aliases.sh`](../scripts/install-shell-aliases.sh) (both `init_*_session.sh` call it). Do **not** hand-edit the managed block in `~/.bash_aliases`.

## Why "ass"

Canonical backronym: **A**gent**S**tart**S**tack. Short, memorable, and deliberately cheeky (same spirit as the retired `nut` name).

Performs local-sync from the matching session clone (Claude or Grok) into the canonical local repo (`CANONICAL_LOCAL_REPO` in host `.agentstartstack.env`; defaults to the repo root). **Pwd-oriented:** `cd` to the canonical repo or a session clone, then run `ass` or `ass up` -- no repo-name argument.

**Canonical entry:** [`scripts/ass.sh`](../scripts/ass.sh) (tracked), with implementation in [`scripts/lib/ass-aliases.sh`](../scripts/lib/ass-aliases.sh). After `install-shell-aliases.sh`, your shell defines only a thin `ass()` wrapper that runs `bash scripts/ass.sh`.

Retired names: `s2s`, `land`, `s2ps`, `s2is`, `push`, `ass push`.

## Usage

```bash
ass                 # local-sync handoff (pwd: canonical or session clone)
ass -f              # handoff only from a post-last-ass session clone
ass --ignore-stashes  # handoff without canonical stash prompts
ass new --grok      # create + align a Grok session clone (canonical pwd)
ass new --claude    # create + align a Claude session clone (canonical pwd)
ass prune           # consolidate one session clone into the newest, then remove it
ass status          # ahead/behind origin/main for canonical and session clones
ass list            # session clones for canonical pwd (by origin URL)
ass sync            # align behind session clones to canonical (canonical pwd)
ass up              # local-sync, then git push origin main
ass up -f           # as ass -f, then push
ass up --ignore-stashes  # as ass --ignore-stashes, then push
ass up trim         # consolidate and prune stale session clones
ass up --all        # ass up agentstartstack, refresh consumer submodules
ass dropit <src>    # from a consumer clone: stash generic work upstream
ass --help
ass up --help
ass up trim --help
ass up --all --help
ass dropit --help
```

**`ass`** -- local-sync only: session clone -> canonical local repo. Human reviews before publishing.
Before handoff, **auto-syncs** any session clone behind canonical (no prompt), checks that
canonical is not behind `origin/main` (prompts to ff-only merge if it is), then picks the
session clone **farthest ahead of canonical** for handoff. Prints **pwd**, canonical, every
session clone (ahead/behind canonical), and which clone is selected.

**`ass up`** -- full human handoff: local-sync with the canonical local repo, then publish to `origin/main`. Agents never run `ass up` themselves.

**`-f` / `--force`** -- among session clones for the repo, ignore any initialized **before** the last successful `ass` (tracked in the canonical repo as `.git/agentstartstack-ass-last`). Among the remaining clones, pick the one **farthest ahead of canonical** (tie: newest commit on `main`) -- same rule as default `ass`, but stale pre-ass sessions cannot win. `init_*_session.sh` stamps each align as `.git/agentstartstack-session-init` in the clone. Use when you started a fresh session after the previous ass and an older session clone still exists on disk.

**`--ignore-stashes`** -- skip canonical stash prompts during handoff. Leaves git stashes and uncommitted work in the canonical repo untouched and proceeds with local-sync. Works with `ass` and `ass up` (e.g. `ass --ignore-stashes`, `ass up --ignore-stashes`, `ass -f --ignore-stashes`).

**`ass up --all`** -- template publish plus submodule refresh and bump. Run only from the agentstartstack canonical local repo (not a session clone, not another repo). Local-sync and push agentstartstack, then for every host canonical local repo whose `.gitmodules` references `farscapian/agentstartstack`:

- **No in-flight session clone** -- `git submodule update --remote` to see the delta it would adopt. If that delta is **action-free** (no `CONSUMER-ACTION:` in any producer commit), **auto-commit** the bump (`Bump .agentstartstack to <sha>`) and `git push origin main`. If the delta **carries a `CONSUMER-ACTION:`**, do **not** auto-commit (a blind pointer move would skip the actions) -- restore the submodule and report the consumer under "need agent (actions)" so an agent session reconciles it. Unchanged consumers report "already current".
- **In-flight session clone(s)** -- uncommitted changes, or commits ahead of `local-sync/main`. Auto-committing the canonical bump would turn an in-flight clone's next `ass` into a non-fast-forward, so canonical is left untouched. Instead `ass up --all` drops a gitignored **`.agentstartstack-bump` watch file** in every clone of that consumer (see [The .agentstartstack-bump watch file](workflow.md#the-agentstartstack-bump-watch-file)). The bump then **rides along**: the agent applies the submodule update on its next commit, and the bump reaches canonical via that agent's normal `ass` (a fast-forward). Other clones find canonical already current on their next align and just clear the flag.

The loop is per-consumer resilient: one failure (update, commit, or push) is logged and counted but does not abort the rest. A summary line reports `bumped / already current / flagged (in-flight) / need agent (actions) / failed`.

**Conventions**

| Item | Path |
|------|------|
| Canonical local repo | `CANONICAL_LOCAL_REPO` in `.agentstartstack.env` (defaults to the repo root) |
| Project-roots search | `AGENTSTARTSTACK_PROJECT_ROOTS` (colon-separated dirs holding `<name>/`) |
| Session clones | `~/.claude/worktrees/<name>/*` |
| | `~/.grok/worktrees/<name>/*` |

Session clones are matched by `origin` URL so repos cannot cross-contaminate. Handoff selects the clone **farthest ahead of canonical** (tie: newest commit on `main`). Session clones must never stay behind canonical -- `ass` auto-syncs them before selecting; use `ass sync` to align manually from canonical pwd. Canonical must not lag `origin/main`; `ass` warns and prompts to ff-only merge if it does. With `-f` / `--force`, clones whose session-init stamp is not after the canonical last-ass stamp are excluded first.

## Guards

`ass` refuses to run while long-running tools are active on the canonical local repo (local-sync updates its working tree via `receive.denyCurrentBranch = updateInstead`):

| Repo | Blocks while |
|------|----------------|
| iotstack | `iotstack` / `iotstack.sh` running |
| printstack | `printstack` / `printstack.sh` running |
| wrtstack | `wrtstack (build|flash)` running |

To add a guard for a new project, extend `_ass_guard_active_sessions` in `scripts/lib/ass-aliases.sh` (see Source below).

## Workflow

1. Agent commits in session clone
2. Human reviews (optional): `ass` local-syncs with the canonical local repo
3. Human publishes: `git push origin main` from the canonical local repo, or combine: `ass up`

Agents never run `ass` or `ass up` unless the human explicitly asks.

See [workflow.md](workflow.md) for session align, agent clone paths, and full git policy.

## dropit

`dropit <src> [<dest>]` -- from a **consumer** session clone, copy a generic feature or doc that belongs upstream in agentstartstack into agentstartstack's **latest session clone** (newest by commit, discovered by origin URL), so it can be committed there and flow upstream instead of being forked into the consumer. It implements the "originate upstream, don't fork" rule in [workflow.md](workflow.md).

- Runs **only** from a consumer session clone (under `AGENT_SESSION_CLONE_PARENT`, with a `.agentstartstack` submodule). Refuses from a canonical repo or from agentstartstack's own clone.
- `<dest>` defaults to `<src>`'s path relative to the consumer clone root.
- Copy-only: it does not edit the consumer or commit in the agentstartstack clone. After it copies, review + commit in the agentstartstack clone and hand off with `ass`; if `<src>` was a fork created in the consumer, delete it there.
- Stamps `Dropit-Id: <session-guid>` on single-file drops (when missing) and appends to `.agentstartstack-dropits` in the consumer. See [Dropit + GUID](workflow.md#dropit--guid-traceable-upstream-handoff) in `workflow.md`.

## ass up trim (consolidate and prune)

`ass up trim` **consolidates and prunes** stale agent **session clones** for a consumer.
**Consolidate** rolls uncommitted work from older clones into the newest kept clone
(unless `--no-rollover`). **Prune** archives each stale clone as a verified `.tar.gz`,
then removes the source directory. Clones with commits not yet in `origin/main` are
**kept** and reported for cherry-pick.

**HARD RULE:** session clones may only be removed after archive (see [workflow.md](workflow.md)
HARD RULES). `ass up trim` and `ass prune` are the **only** supported removal paths -- never
`rm -rf` a session clone by hand.

```bash
ass up trim                 # consumer inferred from pwd
ass up trim iotstack        # named consumer
ass up trim --all           # every configured consumer
ass up trim --dry-run       # plan only (never removes clones)
ass up trim --yes           # skip confirmation prompt
ass up trim --keep-latest 2 # keep two newest clones
```

Run from the **canonical** repo (typical workflow: stay in canonical, run `ass up trim` or
`ass up trim <name>`). Trim discovers every session clone for that consumer, picks the
**survivor** (newest commit on `main` -- trim survivor rule; handoff uses farthest ahead of
canonical), consolidates dirty work from
stale clones into the survivor, and prunes the rest. Before acting, it prints **pwd**, the
**canonical** repo, each session clone (HEAD, behind-canonical, dirty/unlanded), and a
**keep/prune plan**. Clones are consolidated and pruned only after `--yes` or an interactive
`y` at the prompt (not on `--dry-run`).

`ass up --all` calls `ass up trim --yes` for each consumer as its final step (opt out with `ASS_UP_ALL_AUTOTRIM=0` in `.agentstartstack.env`). Set `AGENTSTARTSTACK_CLONE_ARCHIVE_DIR` to control where tarballs land (e.g. `~/.iotstack/archives/agent_clones`).

## ass list (session clones)

Lists every agent session clone for the project, discovered by **git origin URL**
(not folder name). Run from the **canonical** repo:

```bash
ass list
```

Shows agent kind (`grok` / `claude` from `.git/agentstartstack-session-agent`), `HEAD`,
commits **behind canonical**, and path. Newest clone first. Use `ass status` for
ahead/behind counts vs `origin/main`.

## ass sync (align clones to canonical)

After you commit or `ass up` from the **canonical** repo, run `ass sync` to pull
those commits into every session clone that is **behind canonical**. Run from the
canonical local repo:

```bash
ass sync
ass sync --dry-run    # plan only
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

`ass status` lists **agent session clones only** (newest first) — not canonical.
Each row shows ahead/behind vs **`origin/main`** and vs **canonical/main**. Reference
SHAs appear in the INFO line and in the table header (not as a data row). Run from the
canonical repo or any session clone (pwd-oriented).

```bash
ass status
```

| Column | Meaning |
|--------|---------|
| **#** | Session clone index (newest first, same order as `ass list`) |
| **agent** | `grok` / `claude` from `.git/agentstartstack-session-agent` |
| **ahead / behind** (first pair) | Vs `origin/main` (ref in header) |
| **ahead / behind** (second pair) | Vs canonical/main (ref in header) |
| **HEAD** | This clone's `main` |
| **path** | Clone directory |

Example: a clone at **1 ahead** of canonical has one commit waiting for `ass` / `ass up`.

## ass prune (archive one clone)

`ass prune` consolidates dirty work from one session clone into the newest clone for the
same consumer, **archives** the target as a verified `.tar.gz`, then removes it. Same
archive-first rule as trim -- if archiving or verification fails, the clone is left in place.

```bash
ass prune                 # pwd must be a session clone to remove
ass prune <clone-path>    # explicit clone to archive and remove
```

## Source

The functions and aliases live in the tracked canonical file
[`scripts/lib/ass-aliases.sh`](../scripts/lib/ass-aliases.sh) -- `_ass_*` helpers and command
functions (`ass`, `ass_up`, `ass_up_trim`, `ass_up_all`, `ass_prune`, `ass_new`,
`ass_status`, `ass_list`, `ass_sync`, `dropit`).
[`scripts/ass.sh`](../scripts/ass.sh) is the subcommand router.

Install / update the thin `ass()` wrapper in your shell:

```bash
scripts/install-shell-aliases.sh
source ~/.bashrc
```

The managed block in `~/.bash_aliases` defines only `ass() { bash "${AGENTSTARTSTACK_ASS_CLI}" "$@"; }`.
All logic stays in the repo. Never hand-edit the managed block.
