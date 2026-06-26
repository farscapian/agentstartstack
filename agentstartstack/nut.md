# nut -- local-sync with canonical local repo

Human-side helper for the AI git workflow step **local-sync** (session clone -> canonical local repo via the `local-sync` remote). Agents commit in the session clone; the human runs `nut` to local-sync with the canonical local repo, reviews, then `git push origin main`.

**Canonical source:** [`scripts/lib/nut-aliases.sh`](../scripts/lib/nut-aliases.sh) (tracked). Install it into your shell with [`scripts/install-shell-aliases.sh`](../scripts/install-shell-aliases.sh) -- which both `init_claude_session.sh` and `init_grok_session.sh` call -- so a managed block in `~/.bash_aliases` is kept in sync automatically. To change behavior, edit the lib file and re-run the installer; do **not** hand-edit `~/.bash_aliases` (the managed block is overwritten on the next run).

## Why "nut"

Canonical backronym: **N**ewest commit **U**ntil **T**ransferred.

Performs local-sync from the matching session clone (Claude or Grok) into the canonical local repo (`CANONICAL_LOCAL_REPO` in host `.agentstartstack.env`; defaults to the repo root). Short to type, works for every project. Name-based lookup (`nut <name>`, `nutupyall`) searches `AGENTSTARTSTACK_PROJECT_ROOTS` -- colon-separated directories that hold your checkouts as `<root>/<name>` -- which the installer seeds from your layout.

Alt backronyms (HEAD is the tip of the current branch, so the puns write themselves):

- `nut` -- **N**udge **U**ntil **T**ip: advance the branch until the newest commit lands on HEAD.
- `nutup` -- **N**udge **U**ntil **T**ip's **U**p, then **P**ush: get HEAD current locally, then push it upstream -- the exact two-step local-sync-then-publish semantics.

Retired names: `s2s`, `land`, `s2ps`, `s2is`, `push`, `nut push`.

## Usage

```bash
nut                 # local-sync with canonical local repo (infer from pwd)
nut iotstack        # explicit repo name, any pwd
nut -f              # local-sync only from a post-last-nut session clone
nutup               # local-sync, then git push origin main
nutup -f            # as nut -f, then push
nutup iotstack      # local-sync for iotstack, then push
nutupyall           # nutup agentstartstack, refresh consumer submodules
nut --help
nutup --help
nutupyall --help
```

**`nut`** -- local-sync only: session clone -> canonical local repo. Human reviews before publishing.

**`nutup`** -- full human handoff: local-sync with the canonical local repo, then publish to `origin/main`. Agents never run `nutup` themselves.

**`-f` / `--force`** -- among session clones for the repo, ignore any initialized **before** the last successful `nut` (tracked in the canonical repo as `.git/agentstartstack-nut-last`). Among the remaining clones, pick the one with the newest commit on `main` -- same rule as default `nut`, but stale pre-nut sessions cannot win. `init_*_session.sh` stamps each align as `.git/agentstartstack-session-init` in the clone. Use when you started a fresh session after the previous nut and an older session clone still exists on disk.

**`nutupyall`** -- template publish plus submodule refresh and bump. Run only from the agentstartstack canonical local repo (not a session clone, not another repo). Local-sync and push agentstartstack, then for every host canonical local repo whose `.gitmodules` references `farscapian/agentstartstack`:

- **No in-flight session clone** -- `git submodule update --remote` to see the delta it would adopt. If that delta is **action-free** (no `CONSUMER-ACTION:` in any producer commit), **auto-commit** the bump (`Bump .agentstartstack to <sha>`) and `git push origin main`. If the delta **carries a `CONSUMER-ACTION:`**, do **not** auto-commit (a blind pointer move would skip the actions) -- restore the submodule and report the consumer under "need agent (actions)" so an agent session reconciles it. Unchanged consumers report "already current".
- **In-flight session clone(s)** -- uncommitted changes, or commits ahead of `local-sync/main`. Auto-committing the canonical bump would turn an in-flight clone's next `nut` into a non-fast-forward, so canonical is left untouched. Instead `nutupyall` drops a gitignored **`.agentstartstack-bump` watch file** in every clone of that consumer (see [The .agentstartstack-bump watch file](workflow.md#the-agentstartstack-bump-watch-file)). The bump then **rides along**: the agent applies the submodule update on its next commit, and the bump reaches canonical via that agent's normal `nut` (a fast-forward). Other clones find canonical already current on their next align and just clear the flag.

The loop is per-consumer resilient: one failure (update, commit, or push) is logged and counted but does not abort the rest. A summary line reports `bumped / already current / flagged (in-flight) / need agent (actions) / failed`.

**Conventions**

| Item | Path |
|------|------|
| Canonical local repo | `CANONICAL_LOCAL_REPO` in `.agentstartstack.env` (defaults to the repo root) |
| Project-roots search | `AGENTSTARTSTACK_PROJECT_ROOTS` (colon-separated dirs holding `<name>/`) |
| Session clones | `~/.claude/worktrees/<name>/*` |
| | `~/.grok/worktrees/<name>/*` |

Session clones are matched by `origin` URL so repos cannot cross-contaminate. Among matches, the clone with the newest commit on `main` wins. With `-f` / `--force`, clones whose session-init stamp is not after the canonical last-nut stamp are excluded first.

## Guards

`nut` refuses to run while long-running tools are active on the canonical local repo (local-sync updates its working tree via `receive.denyCurrentBranch = updateInstead`):

| Repo | Blocks while |
|------|----------------|
| iotstack | `iotstack` / `iotstack.sh` running |
| printstack | `printstack` / `printstack.sh` running |
| wrtstack | `wrtstack (build|flash)` running |

To add a guard for a new project, extend `_nut_guard_active_sessions` in `~/.bash_aliases` (see Source below).

## Workflow

1. Agent commits in session clone
2. Human reviews (optional): `nut` local-syncs with the canonical local repo
3. Human publishes: `git push origin main` from the canonical local repo, or combine: `nutup`

Agents never run `nut` or `nutup` unless the human explicitly asks.

See [workflow.md](workflow.md) for session align, agent clone paths, and full git policy.

## dropit

`dropit <src> [<dest>]` -- from a **consumer** session clone, copy a generic feature or doc that belongs upstream in agentstartstack into agentstartstack's **latest session clone** (newest by commit, discovered by origin URL), so it can be committed there and flow upstream instead of being forked into the consumer. It implements the "originate upstream, don't fork" rule in [workflow.md](workflow.md).

- Runs **only** from a consumer session clone (under `AGENT_SESSION_CLONE_PARENT`, with a `.agentstartstack` submodule). Refuses from a canonical repo or from agentstartstack's own clone.
- `<dest>` defaults to `<src>`'s path relative to the consumer clone root.
- Copy-only: it does not edit the consumer or commit in the agentstartstack clone. After it copies, review + commit in the agentstartstack clone and hand off with `nut`; if `<src>` was a fork created in the consumer, delete it there.

## Source

The functions and aliases live in the tracked canonical file
[`scripts/lib/nut-aliases.sh`](../scripts/lib/nut-aliases.sh) -- `_nut_*` helpers,
`nut`, `nutup`, `nutitup`, and `nutupyall`. That file is the single source of
truth; this page documents usage only.

Install / update them in your shell:

```bash
# Both init scripts call this; you can also run it directly.
scripts/install-shell-aliases.sh
source ~/.bashrc        # or: source ~/.bash_aliases
```

The installer writes a managed block into `~/.bash_aliases` (overwritten on each
run) and ensures `~/.bashrc` sources it. To add a guard for a new project or
otherwise change behavior, edit `scripts/lib/nut-aliases.sh` and re-run the
installer -- never hand-edit the managed block.
