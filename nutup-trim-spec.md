# Feature request: `nutup trim` (agent session clone pruning)

Status: proposal / handoff for the agentstartstack agent of record.
Dropit-Id: a9116e5e-87cb-49ce-bf20-c1d639a5ee78
Origin: produced from a manual session-clone cleanup performed in a consumer
(iotstack) on 2026-06-25; this spec codifies that procedure as a generic
`nutup` subcommand. It belongs upstream in `scripts/lib/nut-aliases.sh`, not
forked into any consumer.

## Summary

Add a `trim` subcommand to `nutup` that prunes stale agent **session clones**
for a consumer by archiving each as a `.tar.gz` and removing the source
directory. It is generic (multi-consumer) and reuses the clone-discovery and
status helpers already present in `nut-aliases.sh`.

Two behaviors make it safe to keep the working set minimal automatically:

- **Rollover.** Uncommitted changes in an **older** session clone are **rolled
  over into the newest (kept) session clone** before the older clone is
  archived, so the latest agent picks them up for integration -- no in-flight
  work is stranded in a clone that gets removed.
- **Automatic invocation.** `nutupyall` calls `nutup trim` for each consumer it
  processes as a **final step**, so routine handoffs keep the clone set small
  without a separate manual command.

## Command surface

```
nutup trim [<project>] [--all] [--dry-run] [--yes]
           [--no-rollover] [--keep-latest N] [--archive-dir <path>]
```

- `nutup trim` -- operate on the consumer inferred from `$PWD` (same resolution
  `nut`/`nutup` already use).
- `nutup trim <project>` -- target a named consumer.
- `--all` -- iterate every configured consumer.
- `--dry-run` -- print the plan (per-clone classification, rollover target, and
  destination tarballs) and touch nothing.
- `--yes` -- skip the interactive confirmation.
- `--no-rollover` -- do not migrate uncommitted work into the kept clone; an
  older clone with uncommitted changes is then **kept** (reported), not removed.
- `--keep-latest N` -- the N most-recently-modified clones are the **kept set**
  (default 1); they are never archived and serve as the rollover target.
- `--archive-dir <path>` -- override the archive destination.

## Clone discovery

Reuse the existing enumerator -- do not reinvent it:
`_agentstartstack_clones_for_origin "$origin"` (via
`_nutupyall_session_clones "$name"`), which scans `AGENT_SESSION_CLONE_PARENT`
and matches clones by `git remote get-url origin` == the consumer's origin URL.

## Per-clone classification

For each discovered clone:

- `dirty` = `git -C "$clone" status --porcelain` is non-empty.
- `unlanded` = `HEAD` is **not** an ancestor of the consumer's `origin/main`.
  Use the consumer canonical as the reference:
  `git -C "$canonical" fetch -q origin` once, then
  `git -C "$canonical" merge-base --is-ancestor "$(git -C "$clone" rev-parse HEAD)" origin/main`.

  NOTE: this is a **stronger** bar than `nutupyall`'s in-flight test, which
  compares against `local-sync/main` (canonical). `trim` must verify work is
  durable in **origin**, because the source directory is deleted.

- Category (for clones **outside the kept set**):
  - **landed-clean** (`not dirty AND not unlanded`) -> archive + remove.
  - **dirty** (uncommitted changes) -> **roll the uncommitted work over into the
    kept clone** (see [Rollover](#rollover-of-uncommitted-work-mandatory)), then
    archive + remove. Under `--no-rollover`, keep + report instead.
  - **unlanded** (commits not in origin) -> **do not auto-remove.** Report the
    commit subjects so the latest agent cherry-picks them into the kept clone;
    archive + remove only once its committed work is in origin or has been
    cherry-picked.
- The **kept set** = the clone `nutup` is invoked from, plus the `--keep-latest N`
  most-recently-modified clones. The newest clone in the kept set is the
  **rollover target**. Kept clones are never archived.

## Rollover of uncommitted work (mandatory)

Uncommitted work in an older clone must not be lost or stranded when that clone
is removed. Before archiving any **dirty** older clone, migrate its uncommitted
changes into the rollover target (the newest kept clone) so the latest agent
picks them up for integration:

1. Capture the older clone's uncommitted state -- both tracked edits and
   untracked files. A robust capture is `git -C "$old" stash create` (yields a
   commit object holding the dirty state, untracked included with `-u`
   semantics), or a `git -C "$old" diff HEAD` patch plus a list of untracked
   files.
2. Apply it onto the rollover target **non-destructively**: fetch the stash
   commit into the target and `git -C "$target" stash apply`, or
   `git -C "$target" apply --3way` the patch and copy untracked files in. Use a
   3-way / merge apply so context differences (the clones may sit at different
   HEADs) resolve against blob content, not line numbers.
3. **Conflicts are surfaced, never auto-resolved.** Leave conflict markers (or a
   rejected-hunk `.rej`) in the rollover target and report them. The latest
   agent integrates -- that is the point of rolling the work *to* the newest
   session.
4. **Never overwrite the target's own uncommitted work.** If a rolled file
   collides with a change already present in the target, prefer a conflict
   marker over a clobber.
5. Only after the rollover is applied (clean or with surfaced conflicts) does the
   older clone get archived + removed. The archive (full tarball, including the
   original dirty tree) is the backstop if a rollover needs to be re-derived.

If multiple older clones are dirty, roll them over oldest-first into the single
rollover target, so later (newer) changes land on top.

## Archive procedure (safety-critical ordering)

For each clone selected for archiving:

1. `tar czf "$dest/<harness>-<basename>-<shortsha>-<YYYYMMDD>.tar.gz" -C "$parent" "<basename>"`
   (`<harness>` = `claude`/`grok` derived from the parent dir; the tarball
   includes `.git`, so full history **and** uncommitted/un-landed work are
   preserved).
2. **Verify** the tarball is readable: `tar tzf "$tarball" >/dev/null`.
3. **Only if step 2 succeeds**, `rm -rf "$clone"`. On verify failure, leave the
   source in place and report an error. Never delete before a verified archive
   exists.

## Archive destination (configurable, per-consumer)

Resolve in order: `--archive-dir` -> `AGENTSTARTSTACK_CLONE_ARCHIVE_DIR`
(settable in `.agentstartstack.env`) -> a sensible default such as
`${HOME}/.agentstartstack/archives/<project>/agent_clones`. `mkdir -p` it.

iotstack will set `AGENTSTARTSTACK_CLONE_ARCHIVE_DIR=~/.iotstack/archives/agent_clones`
-- match that convention so the consumer controls the path.

## Invocation from `nutupyall` (final step)

`nutupyall` calls `nutup trim` for each consumer it processes, as the **last
step** after its bump propagation, so routine handoffs keep the session-clone set
minimal automatically. Constraints for the automatic call:

- Run it **non-interactively** (`--yes`) but keep every safety invariant:
  verify-before-delete archiving, rollover with surfaced (never auto-resolved)
  conflicts, and the kept-set / never-archive-current rules.
- Honor the active-CLI guard -- skip a consumer whose CLI is running.
- **Opt-out toggle:** a consumer may disable the automatic trim via config
  (e.g. `NUTUPYALL_AUTOTRIM=0` in `.agentstartstack.env`); default is on.
- Fold the trim result into `nutupyall`'s per-consumer summary; one consumer's
  trim failure is logged and counted but does not abort the rest (same
  resilience contract as the rest of `nutupyall`).

## Reporting

Mirror `nutupyall`'s summary style, e.g.:

```
nutup trim: iotstack -- 6 archived, 2 rolled over -> <newest>, 1 kept (unlanded), 1 kept (current)
nutup trim:   rolled over: <old-clone> (3 files; 1 conflict left for agent)
nutup trim:   kept (unlanded): <clone> (2 commit(s) not in origin: <subjects>)
nutup trim: done -- archives in /home/derek/.iotstack/archives/agent_clones
```

For every clone that is rolled over, report the file count and any conflicts
left in the rollover target. For every clone kept due to un-landed commits,
print the commit subjects (`git log --oneline origin/main..HEAD`) so the agent
can cherry-pick them into the kept clone before a later trim removes it -- exactly
the review step that caught two real, un-landed commits during the manual cleanup
this spec is based on.

## Guards / edge cases

- Honor the active-CLI guard (`ACTIVE_GUARD_PGREP`) -- refuse to trim while the
  consumer's CLI is running.
- Session clones are **independent clones**, not `git worktree`s (`.git` is a
  directory), so `rm -rf` is sufficient -- no `git worktree remove`/prune
  needed. Assert `.git` is a directory before removing.
- Default to **non-destructive**: require confirmation unless `--yes`;
  `--dry-run` must produce identical classification output without touching disk.
- A clone carrying only a pending `.agentstartstack-bump` no-op flag is not, by
  itself, in-flight -- classify on `dirty`/`unlanded` only.

## Docs + CONSUMER-ACTION

Update `agentstartstack/workflow.md` and `nut.md` (the nutup section) to document
`trim`. The landing commit should carry a `CONSUMER-ACTION:` telling each
consumer to set `AGENTSTARTSTACK_CLONE_ARCHIVE_DIR` in its `.agentstartstack.env`
(iotstack: `~/.iotstack/archives/agent_clones`) and re-run
`install-shell-aliases.sh`.
