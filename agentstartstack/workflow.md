# Development Workflow

Generic AI agent git workflow for mini-projects. Host projects configure identity via `.agentstartstack.env` at the repo root (created by `scripts/add-to-project.sh`).

## Canonical paths

Substitute `<project>` = `PROJECT_NAME`, `<display>` = `DISPLAY_NAME`, and `<canonical>` = `CANONICAL_LOCAL_REPO` from `.agentstartstack.env`.

| Role | Path |
|------|------|
| Canonical local repo (CLI + daily use) | `<canonical>` on branch `main` (`CANONICAL_LOCAL_REPO`; defaults to the repo root) |
| Grok/Cursor session clones | `~/.grok/worktrees/mini-projects-<project>/<session-id>/` |
| Claude Code session clones | `~/.claude/worktrees/mini-projects-<project>/<session-id>/` |
| Generic agent guidance | `<repo>/agentstartstack/agentstartstack/` |
| Project agent guidance | `<repo>/agentstartstack/` |

Session clones are isolated full git clones (not linked `git worktree` entries). They include the `agentstartstack` submodule when the host repo does.

- **Before testing fixes on the canonical local repo:** `git pull origin main` -- stale trees produce confusing output
- **Handoff between trees:** `origin/main` -- humans push to origin; new sessions align from the canonical local repo

## Who edits where

| Role | Edit here | Why |
|------|-----------|-----|
| Grok/Cursor agent (active session) | `~/.grok/worktrees/mini-projects-<project>/<session-id>/` | Isolated workspace; commits without touching daily tree |
| Claude Code agent (active session) | `~/.claude/worktrees/mini-projects-<project>/<session-id>/` | Same isolation; absolute paths only; VS Code at canonical local repo is reference |
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

Rule of thumb: if the change would help the next project too, it belongs in the template. Flag it; do not fork it.

**Human manual edits:** use the canonical local repo. Edit, test with the project CLI, commit, `git push origin main`. Then align any active agent clone:

```bash
<canonical>/scripts/init_grok_session.sh \
  ~/.grok/worktrees/mini-projects-<project>/<session-id>

<canonical>/scripts/init_claude_session.sh \
  ~/.claude/worktrees/mini-projects-<project>/<session-id>
```

**Mid-session human intervention:** prefer telling the agent what to change. If you must edit git-tracked files yourself, edit the canonical local repo, push, then align the agent clone.

**Testing agent changes:** project CLI always runs from the canonical local repo. After `nut`, pull there if needed, then test.

## AI git workflow

Authorized workflow for agent sessions. Two steps: **session align** at start, **local-sync handoff** after commits.

### 1. Session align (start of session)

Align the session clone with the canonical local repo. Run once per session (or after the human edits the canonical local repo and pushes).

**Idempotency / re-running.** The init scripts are convergent -- re-running lands the clone in the same aligned state -- but the align step is a **hard reset** (`git reset --hard local-sync/main` + `git clean -fd`), which **discards uncommitted work and untracked files** (gitignored files such as `.agentstartstack-bump` survive). The scripts therefore detect a dirty working tree on re-run and prompt before discarding it (a fresh first-run clone is clean, so it never prompts). To merely pick up a pending bump in an active session, do **not** re-run init -- apply the watch file directly (see [The .agentstartstack-bump watch file](#the-agentstartstack-bump-watch-file)).

**Grok/Cursor:** host `scripts/init_grok_session.sh` (wraps `agentstartstack/scripts/init_grok_session.sh`).

```bash
cd ~/.grok/worktrees/mini-projects-<project>/<session-id>
<canonical>/scripts/init_grok_session.sh
```

**Claude Code:** host `scripts/init_claude_session.sh`.

```bash
cd ~/.claude/worktrees/mini-projects-<project>/<session-id>
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
# so nut still matches this clone to the canonical local repo by origin URL.
git remote set-url --push origin DISABLED
```

Session clones have a fetch-only `origin`: `git remote get-url origin` still returns the canonical origin URL (so `nut` can match the clone), but `git push origin ...` fails with `DISABLED`. Handoff is always local-sync (`nut`) from the clone; the push to `origin` happens only from the canonical local repo (`nutup`). The init scripts apply this automatically.

#### Re-align before committing (mandatory)

The align above runs at session start, but the canonical local repo can advance afterward (a human edit, another session's `nut`). Stacking new commits on a stale base is what turns a later `nut` into a rejected non-fast-forward. So **before you add any commit in the session clone, fast-forward it to canonical:**

```bash
# From the session clone, before you start committing:
git fetch local-sync main
git merge --ff-only local-sync/main   # fast-forward the clone up to canonical
```

If `--ff-only` fails, the clone and canonical have **diverged** (the clone holds commits canonical lacks, or both moved). STOP -- do not commit on top. Reconcile first (rebase your clone commits onto `local-sync/main`, or ask the human), then continue.

### 2. local-sync (when human asks)

Perform local-sync from the session clone to the canonical local repo. The human reviews and pushes to origin. **Agents never push to origin.**

**Human command:** `nut` (or `nut <project>`) -- see [nut.md](nut.md).

```bash
nut <project>
```

The canonical local repo should have `receive.denyCurrentBranch = updateInstead` so local-sync updates its working tree.

**Human after local-sync:** review in the canonical local repo, then `git push origin main` (or `nutup`).

**Humans editing the canonical local repo directly:** `git push origin main` from there, then align any active agent clone.

### 3. Active CLI sessions (agents -- mandatory)

Do **not** disrupt long-running project CLI commands the human started on the canonical local repo (flash, build, provision, compile, etc.).

#### Before nut / local-sync

Local-sync **if and only if** no blocking process is running. Each project may define `ACTIVE_GUARD_PGREP` in `.agentstartstack.env`:

```bash
# Example: wrtstack
pgrep -af 'wrtstack (build|flash)' || echo "safe to nut"

# Example: iotstack
pgrep -af '(/iotstack\.sh|/iotstack) ' || echo "safe to nut"

# Example: printstack
pgrep -af '(printstack\.sh|/printstack) ' || echo "safe to nut"
```

If anything matches: commit in the session clone, tell the human local-sync is pending, and wait.

#### Before hardware operations

Never compete with the human for the same hardware (USB serial, SD card, block device) while their CLI session is active. Check `ACTIVE_GUARD_PGREP` and project `agentstartstack/` for device-specific rules.

**When in doubt:** ask the human or wait for their running command to finish.

### 4. The `.agentstartstack-bump` watch file

When the human runs `nutupyall` (see [nut.md](nut.md)) and a consumer has an in-flight session clone, `nutupyall` cannot auto-commit the `.agentstartstack` submodule bump in that consumer's canonical repo -- doing so would turn the clone's next `nut` into a non-fast-forward. Instead it drops a watch file at the **root of every session clone** for that consumer:

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

**3. Reconcile this consumer with those changes.** The submodule update only moves the producer content under `.agentstartstack/`. Anything in *this* repo that mirrors, wraps, or depends on the template can drift and must be brought into line with what you just read -- for example:

- thin wrapper scripts (`scripts/init_*.sh`, `scripts/install-githooks.sh`) if the template changed their contract;
- the host `.githooks/pre-commit` and hook wiring if hook behavior changed;
- the root `CLAUDE.md` / project guidance if topics, conventions, or file paths moved or were renamed;
- any host config or copied snippets the template now expects to differ.

If a producer commit only changes internal template files with no host-facing contract change, no host edits are needed -- but you still must read the commits to confirm that.

```bash
# 4. Commit the bump together with any host reconciliation, then drop the flag.
git add .agentstartstack            # plus any host files you reconciled
git commit                          # or include in the commit you were making
rm .agentstartstack-bump
```

The bump (and your reconciliation) then reaches the canonical local repo through your normal `nut` -- a fast-forward, no divergence. Other clones of the same consumer find the canonical already current on their next session align and simply clear their own flag (the submodule update is a no-op). The init scripts also print a reminder at session align if the flag is present.

**Enforcement (pre-commit guard).** The init scripts install a pre-commit hook in the session clone (under `.git/agentstartstack-hooks/`, with `core.hooksPath` pointed at it) that **refuses any commit while `.agentstartstack-bump` is present**, printing the apply-then-remove commands. After applying the bump and removing the flag, commits proceed. The guard then chains to the repo's tracked `.githooks/pre-commit`, so shellcheck and any other checks still run. The guard lives under `.git/` so it survives `reset --hard` + `git clean -fd`.

The guard is installed by `scripts/install-precommit-guard.sh`, which **both** the init scripts **and** `install-githooks.sh` call. So running either installs the same guard -- they cannot diverge, and re-running `install-githooks.sh` re-asserts the guard rather than dropping it. Agents do not need to remember to re-run anything.

Do not edit the watch file or add it to a tracked `.gitignore`; it is managed by `nutupyall` and removed by you when you apply the bump.

#### Acting on the bump delta (mandatory)

Step 2 of the obligation above has you read every producer commit in `$OLD..$NEW`. Beyond inferring host reconciliation, watch for **explicit** instructions: a producer commit may carry a `CONSUMER-ACTION:` line naming a required follow-up (re-run a tool, regenerate a file) that you must perform verbatim.

**The delta is usually more than one commit** -- the human may run `nutup` several times upstream before this consumer updates -- so walk the commits oldest-first and honor *each* one's `CONSUMER-ACTION`. An action published three `nutup`s ago still sits in its own older commit and is still your obligation; it is not always in the newest commit.

```bash
git -C .agentstartstack log --reverse --format='%H%n%B%n----' "$OLD..$NEW"  # full messages, oldest first
```

For each commit, in order: perform its `CONSUMER-ACTION` exactly if present; otherwise the reconciliation in step 3 applies (or the commit needs nothing). Fold every follow-up into the same consumer commit as the bump.

#### Producer side: write the instructions into the commit (mandatory)

When you commit a change **to the template repo** that downstream consumers must act on after they pull it, say so in the commit message -- the commit is the only channel that travels with the bump. Add an explicit, imperative line so consumer agents do not have to reverse-engineer intent:

```
CONSUMER-ACTION: run scripts/ascii-only-sanitize.py from the repo root and
commit any resulting doc fixups alongside the submodule bump.
```

**Put the line in the same commit that introduces the change -- not in a later "summary" commit.** A consumer may not update its submodule until several `nutup`s later, and it reads every commit in the delta oldest-first; an action only reaches it if it rides the commit that actually made the change. One commit, one self-contained action. If a single commit needs multiple steps, list multiple `CONSUMER-ACTION:` lines in it.

Keep each line specific (exact command, exact follow-up). If a template change is self-contained and needs nothing downstream, no line is needed -- absence of a `CONSUMER-ACTION:` line means "bump and go" for that commit. Right before a `nut`/`nutup` that publishes such a change, confirm the action line rode the correct commit (the one carrying the change), since that is the commit consumers will read it from.

## Watching live CLI runs (agents)

When the human runs the project CLI from the canonical local repo, **watch logs proactively** -- do not wait for them to paste output.

| Pattern | Where to configure |
|---------|-------------------|
| Session registry file (TSV) | Project `agentstartstack/workflow.md` or `cli.md` (e.g. iotstack `sessions.watch`) |
| Terminal milestones | Project `agentstartstack/` |
| `--create-log` session logs | Project `agentstartstack/cli.md` |

Generic rules:
- Tail registry or log files; report milestones and errors in chat
- Read-only inspection is safe while a run is active
- **Unsafe while active:** `git pull` on the canonical local repo, killing the human's process (unless asked), competing hardware access

## End-to-end (quick reference)

**Start a Grok session**
1. Open the session folder in Cursor/Grok
2. Run `scripts/init_grok_session.sh` (session align + goal prompt + agent tips)
3. Paste the suggested first message (task + 1-3 guidance files)

**Start a Claude Code session**
1. Clone: `git clone --recurse-submodules <ORIGIN_URL> ~/.claude/worktrees/mini-projects-<project>/<session-id>`
2. Run `scripts/init_claude_session.sh`
3. VS Code stays at the canonical local repo for reference; Claude Code edits the clone only

**During any agent session**
- Agent edits and commits only in the session clone; never in the canonical local repo
- Load generic guidance from `agentstartstack/agentstartstack/` and project guidance from `agentstartstack/`
- When the human runs CLI on the canonical local repo, watch logs per project docs

**After agent work**
- Human: `nut` (never `git push origin` from agents)
- Human reviews in the canonical local repo, then `git push origin main` or `nutup`

**Human-only work**
- Edit, commit, push from the canonical local repo only
- Next agent session picks up via init scripts

## Agent session clones

```bash
ls -la ~/.grok/worktrees/mini-projects-<project>/
ls -la ~/.claude/worktrees/mini-projects-<project>/
```

Create a new Claude Code session clone:

```bash
git clone --recurse-submodules <ORIGIN_URL> \
  ~/.claude/worktrees/mini-projects-<project>/<session-id>
<canonical>/scripts/init_claude_session.sh \
  ~/.claude/worktrees/mini-projects-<project>/<session-id>
```

## Git hooks (shellcheck)

Install once per clone (canonical local repo or session):

```bash
./scripts/install-githooks.sh
```

Pre-commit runs `shellcheck -x -S error` on staged `.sh` files. See [code-quality.md](code-quality.md).

## Git and commit policy

**Agent default:** commit when a task is complete. Human runs `nut` when ready; `nut` may refuse while CLI is running. Never push to origin.

**Correctness bar:** real hardware / integration testing remains the human's validation standard. Note untested areas in commit messages when relevant.

**Human override:** skip or defer commit when requested (WIP experiments).

### Commit workflow

**Agent (session clone)**
1. Make changes in session clone (never the canonical local repo)
2. `git add` and commit
3. Human: `nut`
4. Human reviews the canonical local repo, then `git push origin main` or `nutup`

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