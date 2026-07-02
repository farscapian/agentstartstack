# Development Workflow

Generic AI agent git workflow for projects. Host projects configure identity via `.agentstartstack.env` at the repo root (created by `scripts/add-to-project.sh`).

## HARD RULES

These rules are non-negotiable for humans and agents working with agentstartstack.

1. **Never hard-reset canonical toward a session clone.** Canonical is authoritative for
   published history. Session clones align *to* canonical via `init_*_session.sh`, not the
   reverse. If canonical and a session clone diverge, use `ass` handoff (session clone ->
   canonical), never `git reset --hard` on canonical to match a session clone.

2. **All session-clone work SHALL be committed automatically.** `init_*_session.sh` runs
   `auto-commit-session-work.sh` after align so agent edits are never left only in the
   working tree (where a mistaken hard-reset would destroy them).

3. **Session clones must not lag canonical.** `ass` auto-syncs any clone behind canonical
   before handoff (no prompt). Canonical must not lag `origin/main`; `ass` warns and prompts
   to ff-only merge `origin/main` if it does.

4. **Session clones SHALL only be removed after archive.** The only permitted way to delete
   a session-clone directory is via `ass drop` or `ass up trim`, which create a verified
   `.tar.gz` under `AGENTSTARTSTACK_CLONE_ARCHIVE_DIR` (or the default archive path) and
   remove the source only after `tar tzf` succeeds. **Never** `rm -rf` a session clone by
   hand, and never delete a clone directory to "sync" or "clean up" canonical. If a clone
   must go, archive it first through `ass`; if the archive step fails, leave the clone in
   place.

5. **Never silently drop the last agent session.** When `ass drop` would remove the
   **last remaining** session clone for a canonical repo, it MUST prompt and proceed only
   on an explicit `y` (even with `--force`). It also refuses to remove the primary clone
   (`#1`/`1*`) or the pwd clone without `--force`, since the active agent session is
   almost always one of those.

## Canonical paths

Substitute `<project>` = `PROJECT_NAME`, `<display>` = `DISPLAY_NAME`, and `<canonical>` = `CANONICAL_LOCAL_REPO` from `.agentstartstack.env`.

| Role | Path |
|------|------|
| Canonical local repo (CLI + daily use) | `<canonical>` on branch `main` (`CANONICAL_LOCAL_REPO`; defaults to the repo root) |
| Agent session worktrees (Grok + Claude) | `~/.grok/worktrees/*`, `~/.claude/worktrees/*` (created by the agents; adopt with `ass adopt`) |
| Generic agent guidance | `<repo>/docs/` |
| Project agent guidance | `<repo>/docs/` |
| CONSUMER-ACTION watermark | `<repo>/.agentstartstack-action-seen` (tracked; consumer only) |
| Dropit ledger | `<repo>/.agentstartstack-dropits` (tracked; consumer only) |

**ass does not create worktrees.** Grok and Claude Code create their own session worktrees under their default roots (`~/.grok/worktrees`, `~/.claude/worktrees`). A worktree may be an independent full clone (`.git` is a directory) or a linked `git worktree` of canonical (`.git` is a gitfile); ass supports both. Make one ass-aware with **`ass adopt <path>`** (writes `.agentstartstack.env` + aligns it); list unrecognized ones with **`ass discover`**.

**Matching:** `ass` matches a worktree to its canonical repo by **git origin URL**, searching under `AGENT_SESSION_CLONE_PARENT` (default `~/.claude/worktrees:~/.grok/worktrees`). The folder name carries no meaning -- no directory-naming scheme is assumed.

**Note:** the old `ass new` command and the unified `~/.ass/worktrees/` location are retired. `ass sync` handoff currently supports full-clone worktrees; linked worktrees are discovered/adopted but their handoff is not yet automated (land their branch into canonical `main` manually).

- **Before testing fixes on the canonical local repo:** `git pull origin main` -- stale trees produce confusing output
- **Handoff between trees:** `origin/main` -- humans push to origin; new sessions align from the canonical local repo

## Who edits where

| Role | Edit here | Why |
|------|-----------|-----|
| Grok/Cursor agent (active session) | `<AGENT_SESSION_CLONE_PARENT>/<session-id>/` | Isolated workspace; commits without touching daily tree |
| Claude Code agent (active session) | `<AGENT_SESSION_CLONE_PARENT>/<session-id>/` | Same isolation; absolute paths only; VS Code at canonical local repo is reference |
| Human (manual work) | `<canonical>` | Primary local repo; CLI runs from here |

**Rule of thumb:** agents write their session clone; humans write the canonical local repo. Do not edit an active session clone by hand.

**Claude Code:** NEVER edit files under `<canonical>` -- use absolute paths to the session clone only.

**Agent write access:** treat the open session clone as agent-owned for the session. Avoid parallel human edits in that directory.

### Generic vs project-specific: where a change originates

Before editing, decide whether a change is **project-specific** or **generic** (useful to every project that consumes this template -- shared tooling, agent guidance, conventions, git-workflow scripts, the sanitizer, hook installers, etc.).

**A consumer-side agent must not hand-edit a generic item into the host project.** Doing so forks it: the fix lives in one consumer, drifts from the template, and never reaches the others. Instead, **advise the human to make the change in the `agentstartstack` template repo**, where it becomes canonical and flows to every consumer via the next submodule bump (see [The .agentstartstack-bump watch file](#the-agentstartstack-bump-watch-file)).

When you spot a generic improvement while working in a consumer project:

1. Name it and state plainly that it is project-non-specific and should originate upstream in `agentstartstack`, not be patched locally.
2. Do **not** apply it in the consumer repo (a local doc symptom of the upstream gap can wait for the corrected tool to flow down and sweep it).
3. Let the human carry it upstream; it returns through the normal bump, and its commit message tells you what to run (see [Acting on the bump delta](#acting-on-the-bump-delta-mandatory)).

If you have actually produced the generic content (a file or doc), use **`ass drop <src> [<dest>]`** from this consumer clone to copy it into agentstartstack's latest session clone -- where it can be reviewed, committed, and flow upstream -- instead of forking it here. Upstream `ass drop` runs only from a consumer session clone and never edits the consumer or the agentstartstack clone's history (see [ass.md](ass.md)).

#### Dropit + GUID: traceable upstream handoff

Flagging a generic improvement can go further than a verbal note: a consumer-side agent may **drop** a written spec/proposal file into an upstream `agentstartstack` session clone for the agent of record to implement (a "dropit"). To make the round trip traceable, the dropit carries a correlation handle.

**When a dropit occurs, the consumer agent SHALL:**

1. **Do NOT generate a new GUID** (no `uuidgen`). Reference the agent's **own session ID** -- the `<session-id>` directory name under `AGENT_SESSION_CLONE_PARENT` (recommended: the unix timestamp from session creation). That id already uniquely identifies the originating agent session, and reusing it is what lets the *same* agent recognize its own dropit when the implementation returns. Stamp it on the dropped file as a header line:
   ```
   Dropit-Id: <session-guid>
   ```
   (`ass drop` stamps this automatically on single-file drops when missing.)
2. Record the same session GUID in a **tracked** consumer-side ledger at the consumer repo root -- `.agentstartstack-dropits` -- one line per outstanding dropit: `<session-guid>  <short description>`. This is the consumer agent's memory that an upstream request is in flight. (`ass drop` appends this line automatically.)

**When `agentstartstack` implements the functionality**, the producer commit that lands it SHALL reference the same GUID in its message:
```
Resolves-Dropit: <guid>
```
(one self-contained line per resolved dropit, on the commit that introduces the implementation -- same discipline as `CONSUMER-ACTION:`).

**On the consumer's next bump**, while walking the producer commits in the delta (see [Acting on the bump delta](#acting-on-the-bump-delta-mandatory)), the consumer agent matches any `Resolves-Dropit: <guid>` against its `.agentstartstack-dropits` ledger. A match means the requested work has **landed upstream**: the consumer agent SHALL then **reconcile** -- remove any local stopgap it was carrying, adopt the upstream implementation, and delete the satisfied line from `.agentstartstack-dropits`.

**`agentstartstack` is authoritative.** If the landed implementation diverges from the dropped spec, the upstream version wins; the consumer reconciles to it rather than re-litigating the spec. The dropit is a request and a trace handle, not a contract.

Rule of thumb: if the change would help the next project too, it belongs in the template. Flag it; do not fork it.

**Human manual edits:** use the canonical local repo. Edit, test with the project CLI, commit, `git push origin main`. Then align any active agent clone:

```bash
<canonical>/scripts/init_grok_session.sh <session-clone-path>
<canonical>/scripts/init_claude_session.sh <session-clone-path>
```

**Mid-session human intervention:** prefer telling the agent what to change. If you must edit git-tracked files yourself, edit the canonical local repo, push, then align the agent clone.

**Testing agent changes:** project CLI always runs from the canonical local repo. After `ass`, pull there if needed, then test.

## AI git workflow

Authorized workflow for agent sessions. Two steps: **session align** at start, **local-sync handoff** after commits.

### 1. Session align (start of session)

Align the session clone with the canonical local repo. Run once per session (or after the human edits the canonical local repo and pushes).

**Idempotency / re-running.** The init scripts are convergent -- re-running lands the clone in the same aligned state -- but the align step is a **hard reset** (`git reset --hard local-sync/main` + `git clean -fd`), which **discards uncommitted work and untracked files** (gitignored files such as `.agentstartstack-bump` survive). The scripts therefore detect a dirty working tree on re-run and prompt before discarding it (a fresh first-run clone is clean, so it never prompts). To merely pick up a pending bump in an active session, do **not** re-run init -- apply the watch file directly (see [The .agentstartstack-bump watch file](#the-agentstartstack-bump-watch-file)).

**Grok/Cursor:** host `scripts/init_grok_session.sh` (wraps `docs/scripts/init_grok_session.sh`).

```bash
cd <AGENT_SESSION_CLONE_PARENT>/<session-id>
<canonical>/scripts/init_grok_session.sh
```

**Claude Code:** host `scripts/init_claude_session.sh`.

```bash
cd <AGENT_SESSION_CLONE_PARENT>/<session-id>
<canonical>/scripts/init_claude_session.sh
```

Manual equivalent:

```bash
cd <session-clone-path>

git remote add local-sync <canonical> 2>/dev/null \
  || git remote set-url local-sync <canonical>

git fetch local-sync main
git reset --hard local-sync/main
git clean -fd
git submodule update --init --recursive

# Harden origin to fetch-only -- agents hand off via local-sync and never push to
# origin. Disabling the push URL makes that structural; the fetch URL stays intact
# so ass still matches this clone to the canonical local repo by origin URL.
git remote set-url --push origin DISABLED
```

Session clones have a fetch-only `origin`: `git remote get-url origin` still returns the canonical origin URL (so `ass` can match the clone), but `git push origin ...` fails with `DISABLED`. Handoff is always local-sync (`ass`) from the clone; the push to `origin` happens only from the canonical local repo (`ass up`). The init scripts apply this automatically.

#### Re-align before committing (mandatory)

The align above runs at session start, but the canonical local repo can advance afterward (a human edit, another session's `ass`). Stacking new commits on a stale base is what turns a later `ass` into a rejected non-fast-forward. So **before you add any commit in the session clone, fast-forward it to canonical:**

```bash
# From the session clone, before you start committing:
git fetch local-sync main
git merge --ff-only local-sync/main   # fast-forward the clone up to canonical
```

If `--ff-only` fails, the clone and canonical have **diverged** (the clone holds commits canonical lacks, or both moved). STOP -- do not commit on top. Reconcile first (rebase your clone commits onto `local-sync/main`, or ask the human), then continue.

#### Never amend a commit already handed off (canonical wins)

**Canonical is authoritative for published history (HARD RULE 1).** Once a commit
has been landed to canonical via `ass`, do **not** `git commit --amend` / rebase /
reword it in the session clone -- that rewrites published history and makes the
clone a *sibling* of canonical, not a descendant.

- A pure reword (message-only amend, same tree) is harmless but pointless: `ass sync`
  rebases the clone onto canonical, sees the patch is already applied, and **drops
  the reworded commit** -- the clone realigns to canonical and canonical's original
  message stays. You cannot change a published commit's message via handoff.
- An amend that **adds/changes content** conflicts on rebase. `ass sync` aborts
  (leaving the clone clean, commits intact) because canonical wins. Re-apply only
  your **net-new** changes as a fresh commit on top of canonical:
  ```bash
  git reset --soft local-sync/main   # keep your tree, drop the rewritten sibling
  git commit                          # net delta as a new commit on top of canonical
  ```

If you need to change something already in canonical, make a **follow-up commit** --
never rewrite the synced one.

### 2. local-sync (when human asks)

Perform local-sync from the session clone to the canonical local repo. The human reviews and pushes to origin. **Agents never push to origin.**

**Human command:** `ass` (or `ass <project>`) -- see [ass.md](ass.md).

```bash
ass <project>
```

The canonical local repo should have `receive.denyCurrentBranch = updateInstead` so local-sync updates its working tree.

**Human after local-sync:** review in the canonical local repo, then `git push origin main` (or `ass up`).

**Humans editing the canonical local repo directly:** `git push origin main` from there, then align any active agent clone.

### 3. Active CLI sessions (agents -- mandatory)

Do **not** disrupt long-running project CLI commands the human started on the canonical local repo (flash, build, provision, compile, etc.).

#### Before ass / local-sync

Local-sync **if and only if** no blocking process is running. Each project may define `ACTIVE_GUARD_PGREP` in `.agentstartstack.env`:

```bash
# Example: wrtstack
pgrep -af 'wrtstack (build|flash)' || echo "safe to ass"

# Example: iotstack
pgrep -af '(/iotstack\.sh|/iotstack) ' || echo "safe to ass"

# Example: printstack
pgrep -af '(printstack\.sh|/printstack) ' || echo "safe to ass"
```

If anything matches: commit in the session clone, tell the human local-sync is pending, and wait.

#### Before hardware operations

Never compete with the human for the same hardware (USB serial, SD card, block device) while their CLI session is active. Check `ACTIVE_GUARD_PGREP` and project `docs/` for device-specific rules.

**When in doubt:** ask the human or wait for their running command to finish.

### 4. The `.agentstartstack-bump` watch file

When the human runs `ass publish` (see [ass.md](ass.md)) and a consumer has an in-flight session clone, `ass publish` cannot auto-commit the `.agentstartstack` submodule bump in that consumer's canonical repo -- doing so would turn the clone's next `ass` into a non-fast-forward. Instead it drops a watch file at the **root of every session clone** for that consumer:

```
.agentstartstack-bump
```

The file is gitignored via `.git/info/exclude`, so it never shows in `git status`, is never committed, and survives `reset --hard` + `git clean -fd`. Its presence means: *a newer agentstartstack is published; pull it into this clone.*

**Agent obligation (mandatory):** any time you are about to make a commit you initiated, first check for `.agentstartstack-bump` at the clone root. If it exists, **do not just bump the pointer** -- read what changed in the producer and reconcile this consumer's own copy with it:

```bash
# 1. Record the SHA you are moving FROM, then advance the submodule.
OLD=$(git -C .agentstartstack rev-parse HEAD)
git submodule update --init --recursive --remote .agentstartstack
NEW=$(git -C .agentstartstack rev-parse HEAD)

# 2. READ the producer commits you are adopting -- messages and diffs.
git -C .agentstartstack log --oneline "$OLD..$NEW"
git -C .agentstartstack diff "$OLD..$NEW"
```

**3. Reconcile this consumer with those changes.** The submodule update only moves the producer content under `.docs/`. Anything in *this* repo that mirrors, wraps, or depends on the template can drift and must be brought into line with what you just read -- for example:

- thin wrapper scripts (`scripts/init_*.sh`, `scripts/install-githooks.sh`) if the template changed their contract;
- the host `.githooks/pre-commit` and hook wiring if hook behavior changed;
- the root `CLAUDE.md` / project guidance if topics, conventions, or file paths moved or were renamed;
- any host config or copied snippets the template now expects to differ.

If a producer commit only changes internal template files with no host-facing contract change, no host edits are needed -- but you still must read the commits to confirm that.

```bash
# 4. Record the CONSUMER-ACTION watermark when the delta had actions (see below).
# 5. Commit the bump together with any host reconciliation, then drop the flag.
.docs/scripts/record-consumer-action-seen.sh "$OLD" "$NEW"
git add .agentstartstack .agentstartstack-action-seen   # plus any host files you reconciled
git commit                          # or include in the commit you were making
rm .agentstartstack-bump
```

The bump (and your reconciliation) then reaches the canonical local repo through your normal `ass` -- a fast-forward, no divergence. Other clones of the same consumer find the canonical already current on their next session align and simply clear their own flag (the submodule update is a no-op). The init scripts also print a reminder at session align if the flag is present.

**Enforcement (pre-commit guard).** The init scripts install a pre-commit hook in the session clone (under `.git/agentstartstack-hooks/`, with `core.hooksPath` pointed at it) that **refuses any commit while `.agentstartstack-bump` is present**, printing the apply-then-remove commands. After applying the bump and removing the flag, commits proceed. The guard then chains to the repo's tracked `.githooks/pre-commit`, so shellcheck and any other checks still run. The guard lives under `.git/` so it survives `reset --hard` + `git clean -fd`.

The guard is installed by `scripts/install-precommit-guard.sh`, which **both** the init scripts **and** `install-githooks.sh` call. So running either installs the same guard -- they cannot diverge, and re-running `install-githooks.sh` re-asserts the guard rather than dropping it. Agents do not need to remember to re-run anything.

Do not edit the watch file or add it to a tracked `.gitignore`; it is managed by `ass publish` and removed by you when you apply the bump.

#### Acting on the bump delta (mandatory)

Step 2 of the obligation above has you read every producer commit in `$OLD..$NEW`. Beyond inferring host reconciliation, watch for **explicit** instructions: a producer commit may carry a `CONSUMER-ACTION:` line naming a required follow-up (re-run a tool, regenerate a file) that you must perform verbatim.

**The delta is usually more than one commit** -- the human may run `ass up` several times upstream before this consumer updates -- so walk the commits oldest-first and honor *each* one's `CONSUMER-ACTION`. An action published three `ass up`s ago still sits in its own older commit and is still your obligation; it is not always in the newest commit.

```bash
git -C .agentstartstack log --reverse --format='%H%n%B%n----' "$OLD..$NEW"  # full messages, oldest first
```

For each commit, in order: perform its `CONSUMER-ACTION` exactly if present; match any `Resolves-Dropit: <guid>` against `.agentstartstack-dropits` and reconcile satisfied dropits; otherwise the reconciliation in step 3 applies (or the commit needs nothing). Fold every follow-up into the same consumer commit as the bump.

#### CONSUMER-ACTION watermark (mandatory)

A consumer repo **SHALL** record the latest `agentstartstack` submodule commit it has **seen and acted on** whose message carries a `CONSUMER-ACTION:` line. Persist it as a **tracked** one-line file at the consumer repo root:

```
.agentstartstack-action-seen
```

The file holds a single full 40-character git SHA (no prefix). It is the watermark for which explicit producer actions are already done -- not the submodule pointer itself. A consumer can be current on `.agentstartstack` at `HEAD` and still owe actions if the watermark lags; conversely, an action-free bump does not advance the watermark.

**When to update (mandatory):** immediately after you perform every `CONSUMER-ACTION` in the delta you just reconciled (`$OLD..$NEW`), set the watermark to the **newest** producer commit in that delta that carries `CONSUMER-ACTION:` (not merely `$NEW` when the tip commit is action-free). Commit `.agentstartstack-action-seen` in the **same consumer commit** as the submodule bump and any host reconciliation.

```bash
# After steps 1-3 above and every CONSUMER-ACTION in the delta is done:
.docs/scripts/record-consumer-action-seen.sh "$OLD" "$NEW"
git add .agentstartstack-action-seen   # plus .agentstartstack and any host files
```

If `$OLD..$NEW` is action-free, leave the watermark unchanged (the script is a no-op). Do not hand-edit the SHA except during the one-time stale-consumer catch-up below.

**Init backstop.** `init_*_session.sh` calls `agentstartstack_pending_consumer_actions`: when the submodule pointer is already current but any `CONSUMER-ACTION` in `(watermark..HEAD]` remains unperformed, session align prints the pending range and points here. This catches consumers that advanced the pointer without reconciling (for example a pre-action-aware blind auto-bump).

**No watermark yet.** Pre-protocol consumers may lack the file. After you finish the [one-time stale catch-up](#remediating-a-stale-consumer-one-time), create `.agentstartstack-action-seen` at the latest historical `CONSUMER-ACTION` commit you applied (same commit command as above, using that catch-up delta's `$OLD`/`$NEW`).

#### Producer side: write the instructions into the commit (mandatory)

When you commit a change **to the template repo** that downstream consumers must act on after they pull it, say so in the commit message -- the commit is the only channel that travels with the bump. Add an explicit, imperative line so consumer agents do not have to reverse-engineer intent:

```
CONSUMER-ACTION: run scripts/ascii-only-sanitize.py from the repo root and
commit any resulting doc fixups alongside the submodule bump.
```

**Put the line in the same commit that introduces the change -- not in a later "summary" commit.** A consumer may not update its submodule until several `ass up`s later, and it reads every commit in the delta oldest-first; an action only reaches it if it rides the commit that actually made the change. One commit, one self-contained action. If a single commit needs multiple steps, list multiple `CONSUMER-ACTION:` lines in it.

Keep each line specific (exact command, exact follow-up). If a template change is self-contained and needs nothing downstream, no line is needed -- absence of a `CONSUMER-ACTION:` line means "bump and go" for that commit. Right before a `ass`/`ass up` that publishes such a change, confirm the action line rode the correct commit (the one carrying the change), since that is the commit consumers will read it from.

#### ass publish is action-aware; init backstops it

`ass publish` propagates a bump to each consumer by one of two paths, and **neither blind-bumps past a `CONSUMER-ACTION`**:

- **In-flight session clone** -> drops the `.agentstartstack-bump` watch file; the agent reads the delta and reconciles (per the obligation above).
- **No in-flight clone** -> `ass publish` reads the delta (`OLD..NEW`) it would adopt:
  - **action-free delta** -> safe to auto-commit the bump in the consumer canonical and push (the fast path).
  - **delta carries any `CONSUMER-ACTION:`** -> `ass publish` does **not** auto-commit. It restores the submodule to its committed SHA and reports the consumer under "need agent (actions)". The bump waits until an agent session reconciles it; auto-committing would silently skip the actions.

**Init backstop.** Independently of any watch file, `init_*_session.sh` checks at align time whether the `.agentstartstack` submodule is behind its remote (`agentstartstack_pending_reconcile`). If so it prints the pending `OLD..NEW` range and the read-and-reconcile commands, so a deferred bump is caught on the next session even with no watch file present.

#### Remediating a stale consumer (one-time)

A consumer bumped **before** the action-aware fix may have had `CONSUMER-ACTION`s silently skipped by the old blind auto-commit -- its submodule pointer advanced but its own copy/config never reconciled. Such a consumer is *not* "behind its remote", so the init backstop will not flag it. Remediate once, by hand:

1. List every action ever published up to the current pointer and apply any not yet done (they are written to be idempotent):
   ```bash
   git -C .agentstartstack log --reverse --format='%H %s%n%b' | grep -B1 '^[[:space:]]*CONSUMER-ACTION:'
   ```
2. In practice: re-run `.docs/scripts/ascii-only-sanitize.py` over the repo; re-run `.docs/scripts/install-shell-aliases.sh` then `source ~/.bashrc`; in `.agentstartstack.env` rename `SYNC_REPO`->`CANONICAL_LOCAL_REPO` and `CLAUDE_PARENT`/`GROK_PARENT`->`AGENT_SESSION_CLONE_PARENT` if set; migrate a project `docs/` docs dir to `docs/`.
3. Record the watermark for every historical action you just performed, then commit the reconciliation:
   ```bash
   OLD=$(git -C .agentstartstack rev-list --max-parents=0 HEAD)
   NEW=$(git -C .agentstartstack rev-parse HEAD)
   .docs/scripts/record-consumer-action-seen.sh "$OLD" "$NEW"
   git add .agentstartstack-action-seen   # plus any host files you reconciled
   git commit -m "Reconcile agentstartstack CONSUMER-ACTION backlog"
   ```

New bumps are protected by the action-aware path, the watermark, and the init backstops; this catch-up is only for the pre-fix gap.

## Watching live CLI runs (agents)

When the human runs the project CLI from the canonical local repo, **watch logs proactively** -- do not wait for them to paste output.

| Pattern | Where to configure |
|---------|-------------------|
| Session registry file (TSV) | Project `docs/workflow.md` or `cli.md` (e.g. iotstack `sessions.watch`) |
| Terminal milestones | Project `docs/` |
| `--create-log` session logs | Project `docs/cli.md` |

Generic rules:
- Tail registry or log files; report milestones and errors in chat
- Read-only inspection is safe while a run is active
- **Unsafe while active:** `git pull` on the canonical local repo, killing the human's process (unless asked), competing hardware access

## End-to-end (quick reference)

**Start any agent session (Grok or Claude)**

Let the agent create its own worktree in its default location, then make it
ass-aware and align it with **`ass adopt`**.

```bash
# 1. Create a worktree the agent's own way (under ~/.grok/worktrees or
#    ~/.claude/worktrees), e.g. grok --worktree / Claude Code's worktree feature.

# 2. Adopt + align it (writes .agentstartstack.env, runs init) -- point at the worktree
ass adopt ~/.claude/worktrees/<name>      # or --grok / --claude to force the agent
#    (or: from <canonical>, run 'ass discover --adopt' to adopt all new worktrees)

# 3. Work in that worktree with the agent (grok / claude).
```

`AGENT_SESSION_CLONE_PARENT` (colon-separated search roots) defaults to
`~/.claude/worktrees:~/.grok/worktrees` for discovery. ass does not create
worktrees; `ass adopt` provisions an agent-created one, `ass discover` lists them.

**Grok/Cursor after align:** paste the suggested first message from `init_grok_session.sh` (task + 1-3 guidance files).

**Claude Code after align:** VS Code stays at `<canonical>` for the human's reference; Claude edits the session clone only (absolute paths).

**During any agent session**
- Agent edits and commits only in the session clone; never in the canonical local repo
- Load generic guidance from `docs/` and project guidance from `docs/`
- When the human runs CLI on the canonical local repo, watch logs per project docs

**After agent work**
- Human: `ass` (never `git push origin` from agents)
- Human reviews in the canonical local repo, then `git push origin main` or `ass up`

**Human-only work**
- Edit, commit, push from the canonical local repo only
- Next agent session picks up via init scripts

## Agent session clones

### Configuration

`AGENT_SESSION_CLONE_PARENT` is the colon-separated list of directories `ass` searches for session worktrees (by git origin URL). It is read from `.agentstartstack.env` by the init scripts and from the environment (after `source ~/.bashrc`) by `ass` / `ass up trim`. Default: `~/.claude/worktrees:~/.grok/worktrees`.

**ass does not create worktrees.** Grok/Claude create them under their own roots; `ass adopt <path>` writes `.agentstartstack.env` and aligns an agent-created worktree, and the init scripts do the alignment. `ass discover` lists agent worktrees for the repo and their adopt status.

### Removing session clones (archive first)

Session-clone directories are **archived, not deleted outright**. Use:

- `ass drop` -- archive every session clone except #1 (collapse into one; run from canonical)
- `ass drop <n>` -- archive one clone by index from `ass list` / `ass status`
- `ass up trim` -- batch consolidate + archive stale clones (typical; run from canonical)

Both call the same archive path: tarball under `AGENTSTARTSTACK_CLONE_ARCHIVE_DIR` (default
`~/.agentstartstack/archives/<project>/agent_clones/`), verify the archive, then remove the
source tree. There is **no** supported manual `rm -rf` of a session clone. Aligning a clone
(`init_*_session.sh`) may `git clean -fd` *inside* an existing clone; that is not removal of
the clone directory itself.

**Never** delete a session-clone folder to fix canonical/session drift, and never remove a
clone while a Grok/Claude session is still open on that path -- restart or close the session
first, then `ass drop` or `ass up trim`.

### Listing clones

From the **canonical** repo:

```bash
ass list
```

`ass` discovers clones by origin URL, not folder name. For ahead/behind vs GitHub, use
`ass status`.

Or list the agent worktree roots directly:

```bash
ls -la "${HOME}/.claude/worktrees/" "${HOME}/.grok/worktrees/"
```

### Adopt an agent-created worktree

ass does not create worktrees -- let the agent create one its own way, then adopt it:

```bash
# 1. Create the worktree the agent's own way, e.g.:
grok --worktree            # -> ~/.grok/worktrees/<name>
# or use Claude Code's worktree feature -> ~/.claude/worktrees/<name>

# 2. From <canonical>, discover + adopt (writes .agentstartstack.env, runs init):
ass discover --adopt
#    or adopt a specific path (force the agent with --grok/--claude if needed):
ass adopt ~/.claude/worktrees/<name>

# 3. Work in that worktree with the agent (grok / claude).
```

Both worktree kinds are supported: an independent full clone (`.git` is a
directory) and a linked `git worktree` of canonical (`.git` is a gitfile). Note
that `ass sync` handoff currently automates only full-clone worktrees; a linked
worktree is discovered/adopted, but land its branch into canonical `main`
manually for now (it shares canonical's object store, so no push handoff applies).

## Git hooks (shellcheck)

Install once per clone (canonical local repo or session):

```bash
./scripts/install-githooks.sh
```

Pre-commit runs `shellcheck -x -S error` on staged `.sh` files. See [code-quality.md](code-quality.md).

## Git and commit policy

**Agent default:** commit when a task is complete. Human runs `ass sync` when ready; `ass sync` may refuse while CLI is running. Never push to origin.

**Correctness bar:** real hardware / integration testing remains the human's validation standard. Note untested areas in commit messages when relevant.

**Human override:** skip or defer commit when requested (WIP experiments).

### Commit workflow

**Agent (session clone)**
1. Make changes in session clone (never the canonical local repo)
2. `git add` and commit
3. Human: `ass`
4. Human reviews the canonical local repo, then `git push origin main` or `ass up`

**Human (canonical local repo)**
1. Edit there, commit, `git push origin main`
2. Align active agent clones before resuming agent work

## Research FIRST, then debug

**When encountering a persistent problem, do targeted internet research BEFORE systematic debugging.**

**When to research:**
- Problem seems common (baud rates, cloud-init, usbip, build failures)
- Infrastructure or embedded systems issue with known community solutions
- Multiple attempts failing with similar symptoms

**When systematic debugging is still appropriate:**
- Project-specific architecture edge cases
- After research has identified the likely cause (then test to confirm)