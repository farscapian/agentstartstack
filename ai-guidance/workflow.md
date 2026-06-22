# Development Workflow

Generic AI agent git workflow for mini-projects. Host projects configure identity via `.agentstartstack.env` at the repo root (created by `scripts/add-to-project.sh`).

## Canonical paths

Substitute `<project>` = `PROJECT_NAME` and `<display>` = `DISPLAY_NAME` from `.agentstartstack.env`.

| Role | Path |
|------|------|
| Primary repo (CLI + daily use) | `~/Sync/mini_projects/<project>` on branch `main` |
| Grok/Cursor session clones | `~/.grok/worktrees/mini-projects-<project>/<session-id>/` |
| Claude Code session clones | `~/.claude/worktrees/mini-projects-<project>/<session-id>/` |
| Generic agent guidance | `<repo>/agentstartstack/ai-guidance/` |
| Project agent guidance | `<repo>/ai-guidance/` |

Session clones are isolated full git clones (not linked `git worktree` entries). They include the `agentstartstack` submodule when the host repo does.

- **Before testing fixes on Sync:** `git pull origin main` -- stale trees produce confusing output
- **Handoff between trees:** `origin/main` -- humans push to origin; new sessions session-sync from Sync

## Who edits where

| Role | Edit here | Why |
|------|-----------|-----|
| Grok/Cursor agent (active session) | `~/.grok/worktrees/mini-projects-<project>/<session-id>/` | Isolated workspace; commits without touching daily tree |
| Claude Code agent (active session) | `~/.claude/worktrees/mini-projects-<project>/<session-id>/` | Same isolation; absolute paths only; VS Code at Sync is reference |
| Human (manual work) | `~/Sync/mini_projects/<project>` | Canonical repo; CLI runs from here |

**Rule of thumb:** agents write their session clone; humans write Sync. Do not edit an active session clone by hand.

**Claude Code:** NEVER edit files under `~/Sync/mini_projects/<project>` -- use absolute paths to the session clone only.

**Agent write access:** treat the open session clone as agent-owned for the session. Avoid parallel human edits in that directory.

**Human manual edits:** use Sync. Edit, test with the project CLI, commit, `git push origin main`. Then session-sync any active agent clone:

```bash
~/Sync/mini_projects/<project>/scripts/init_grok_session.sh \
  ~/.grok/worktrees/mini-projects-<project>/<session-id>

~/Sync/mini_projects/<project>/scripts/init_claude_session.sh \
  ~/.claude/worktrees/mini-projects-<project>/<session-id>
```

**Mid-session human intervention:** prefer telling the agent what to change. If you must edit git-tracked files yourself, edit Sync, push, then session-sync the agent clone.

**Testing agent changes:** project CLI always runs from Sync. After `nut`, pull on Sync if needed, then test.

## AI git workflow

Authorized workflow for agent sessions. Two steps: **session sync** at start, **handoff** after commits.

### 1. Session sync (start of session)

Align the session clone with the canonical Sync repo. Run once per session (or after the human edits Sync and pushes).

**Grok/Cursor:** host `scripts/init_grok_session.sh` (wraps `agentstartstack/scripts/init_grok_session.sh`).

```bash
cd ~/.grok/worktrees/mini-projects-<project>/<session-id>
~/Sync/mini_projects/<project>/scripts/init_grok_session.sh
```

**Claude Code:** host `scripts/init_claude_session.sh`.

```bash
cd ~/.claude/worktrees/mini-projects-<project>/<session-id>
~/Sync/mini_projects/<project>/scripts/init_claude_session.sh
```

Manual equivalent:

```bash
cd <session-clone-path>

git remote add local-sync ~/Sync/mini_projects/<project> 2>/dev/null \
  || git remote set-url local-sync ~/Sync/mini_projects/<project>

git fetch local-sync main
git reset --hard local-sync/main
git clean -fd
git submodule update --init --recursive
```

### 2. Sync (when human asks)

Push the latest agent-worktree commit to the local Sync repo. The human reviews and pushes to origin. **Agents never push to origin.**

**Human command:** `nut` (or `nut <project>`) -- see [nut.md](nut.md).

```bash
nut <project>
```

`~/Sync/mini_projects/<project>` should have `receive.denyCurrentBranch = updateInstead` so the push updates Sync's working tree.

**Human after sync:** review in Sync, then `git push origin main` (or `nutup`).

**Humans editing Sync directly:** `git push origin main` from Sync, then session-sync any active agent clone.

### 3. Active CLI sessions (agents -- mandatory)

Do **not** disrupt long-running project CLI commands the human started on Sync (flash, build, provision, compile, etc.).

#### Before nut / sync to Sync

Sync to Sync **if and only if** no blocking process is running. Each project may define `ACTIVE_GUARD_PGREP` in `.agentstartstack.env`:

```bash
# Example: wrtstack
pgrep -af 'wrtstack (build|flash)' || echo "safe to nut"

# Example: iotstack
pgrep -af '(/iotstack\.sh|/iotstack) ' || echo "safe to nut"

# Example: printstack
pgrep -af '(printstack\.sh|/printstack) ' || echo "safe to nut"
```

If anything matches: commit in the session clone, tell the human sync is pending, and wait.

#### Before hardware operations

Never compete with the human for the same hardware (USB serial, SD card, block device) while their CLI session is active. Check `ACTIVE_GUARD_PGREP` and project `ai-guidance/` for device-specific rules.

**When in doubt:** ask the human or wait for their running command to finish.

## Watching live CLI runs (agents)

When the human runs the project CLI from Sync, **watch logs proactively** -- do not wait for them to paste output.

| Pattern | Where to configure |
|---------|-------------------|
| Session registry file (TSV) | Project `ai-guidance/workflow.md` or `cli.md` (e.g. iotstack `sessions.watch`) |
| Terminal milestones | Project `ai-guidance/` |
| `--create-log` session logs | Project `ai-guidance/cli.md` |

Generic rules:
- Tail registry or log files; report milestones and errors in chat
- Read-only inspection is safe while a run is active
- **Unsafe while active:** `git pull` on Sync, killing the human's process (unless asked), competing hardware access

## End-to-end (quick reference)

**Start a Grok session**
1. Open the session folder in Cursor/Grok
2. Run `scripts/init_grok_session.sh` (session sync + goal prompt + agent tips)
3. Paste the suggested first message (task + 1-3 guidance files)

**Start a Claude Code session**
1. Clone: `git clone --recurse-submodules <ORIGIN_URL> ~/.claude/worktrees/mini-projects-<project>/<session-id>`
2. Run `scripts/init_claude_session.sh`
3. VS Code stays at Sync for reference; Claude Code edits the clone only

**During any agent session**
- Agent edits and commits only in the session clone; never in Sync
- Load generic guidance from `agentstartstack/ai-guidance/` and project guidance from `ai-guidance/`
- When the human runs CLI on Sync, watch logs per project docs

**After agent work**
- Human: `nut` (never `git push origin` from agents)
- Human reviews in Sync, then `git push origin main` or `nutup`

**Human-only work**
- Edit, commit, push from Sync only
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
~/Sync/mini_projects/<project>/scripts/init_claude_session.sh \
  ~/.claude/worktrees/mini-projects-<project>/<session-id>
```

## Git hooks (shellcheck)

Install once per clone (Sync or session):

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
1. Make changes in session clone (never Sync)
2. `git add` and commit
3. Human: `nut`
4. Human reviews Sync, then `git push origin main` or `nutup`

**Human (Sync)**
1. Edit on Sync, commit, `git push origin main`
2. Session-sync active agent clones before resuming agent work

## Research FIRST, then debug

**When encountering a persistent problem, do targeted internet research BEFORE systematic debugging.**

**When to research:**
- Problem seems common (baud rates, cloud-init, usbip, build failures)
- Infrastructure or embedded systems issue with known community solutions
- Multiple attempts failing with similar symptoms

**When systematic debugging is still appropriate:**
- Project-specific architecture edge cases
- After research has identified the likely cause (then test to confirm)