# agentstartstack

Shared AI agent guidance and workflow tooling for projects. Add this repo as a **git submodule** at `.agentstartstack/` so every new project starts with the same agent workflows, conventions, and session scripts.

## What you get

| Path (in this repo) | Purpose |
|---------------------|---------|
| `docs/` | Generic agent docs: workflow, ass, conventions, security, terminal tips, etc. |
| `scripts/` | `ass.sh` CLI, `init_grok_session.sh`, `init_claude_session.sh`, git hooks |
| `templates/` | Stubs for wiring a new project (`.agentstartstack.env`, `CLAUDE.md`, project `docs/`) |

When mounted as a submodule in a host project:

| Host path | Purpose |
|-----------|---------|
| `.agentstartstack/` | This repo (submodule) |
| `.agentstartstack/docs/` | Generic guidance |
| `docs/` | Project-specific guidance |

## Quick start (new project)

From an existing project repo (e.g. `wrtstack`):

```bash
# 1. Add submodule
git submodule add git@github.com:farscapian/agentstartstack.git .agentstartstack

# 2. Run the wiring script (creates .agentstartstack.env, wrapper scripts, stubs)
./.agentstartstack/scripts/add-to-project.sh

# 3. Edit .agentstartstack.env and CLAUDE.md for your project
# 4. Commit submodule + new files
git add .agentstartstack .agentstartstack.env CLAUDE.md docs scripts .githooks
git commit -m "Add agentstartstack submodule and AI guidance"
```

Or clone with submodules:

```bash
git clone --recurse-submodules git@github.com:farscapian/<your-project>.git
```

## Agent session workflow (summary)

1. **New session** -- grok/claude create a worktree under their own root (`~/.grok/worktrees`, `~/.claude/worktrees`); make it ass-aware with `ass adopt <path>` (or `ass discover --adopt`)
2. **Work** -- agent edits only its session worktree, never the canonical local repo
3. **Handoff** -- human runs `ass sync` (or `ass up`) from `~/.bash_aliases`; agents never `git push origin`

Full details: [`docs/workflow.md`](docs/workflow.md) and [`docs/ass.md`](docs/ass.md).

## `ass` CLI (human-side handoff)

Entry point: [`scripts/ass.sh`](scripts/ass.sh). After [`scripts/install-shell-aliases.sh`](scripts/install-shell-aliases.sh), your shell defines a thin `ass()` wrapper. **Pwd-oriented:** `cd` to the canonical repo or a session clone, then run a command.

### Handoff

| Command | Description |
|---------|-------------|
| `ass` / `ass help` | Show main help menu |
| `ass sync` | Local-sync session clone -> canonical (pick farthest ahead; auto-sync behind clones) |
| `ass sync -f` | Same, but ignore session clones initialized before the last `ass` |
| `ass sync --stashes` | Opt in: prompt to move canonical stashes into the session clone |
| `ass sync all` | Align every session clone behind canonical (`--dry-run` to preview) |
| `ass up` | `ass sync`, then `git push origin main` |
| `ass up -f` | `ass sync -f`, then push |
| `ass up --stashes` | `ass sync --stashes`, then push |

### Session clones

| Command | Description |
|---------|-------------|
| `ass adopt [PATH]` | Make an agent-created worktree ass-aware (write env + align); `--grok`/`--claude` force the agent |
| `ass discover [--adopt]` | List agent worktrees for this repo + adopt status; `--adopt` provisions unadopted ones |
| `ass list` | List session worktrees for this project (by origin URL) |
| `ass status` | Ahead/behind `origin/main` for canonical and each session clone |
| `ass info <n>` | Plain-language summary for session #n (from `ass status`; includes dirty-work analysis) |

| `ass drop` | Archive all session clones except #1 (collapse into one) |
| `ass drop <n>` | Archive and remove session clone #n (index from `ass list`) |
| `ass drop <src> [dest]` | From a consumer session clone: copy generic work into agentstartstack |

### Trim and publish

| Command | Description |
|---------|-------------|
| `ass up trim` | Roll dirty work into kept clones, archive stale session clones |
| `ass up trim --dry-run` | Print keep/prune/rollover plan only |
| `ass up trim --yes` | Skip confirmation prompt |
| `ass up trim --keep-latest N` | Keep N most-recently-modified clones (default 1) |
| `ass up trim --no-rollover` | Keep dirty older clones instead of rolling work over |
| `ass publish` | `ass up` agentstartstack, then bump `.agentstartstack` in consumers, auto-trim clones |

### Help

Main menu (`ass` / `ass help`) lists **direct subcommands only**. Detailed help
for each command (and nested topics like `sync all`, `up trim`) lives in
`docs/help/*.txt`. See [docs/cli-help.md](docs/cli-help.md).

```bash
ass help
ass help sync
ass sync help
ass up trim help
ass help publish
```

See [`docs/ass.md`](docs/ass.md) for guards, trim/archive rules, and the `ass publish` bump protocol.

### Starting a session (template or host project)

Let the agent create its worktree in its own default location, then adopt it:

```bash
# 1. Create a worktree the agent's way (under ~/.grok/worktrees or ~/.claude/worktrees)
grok --worktree          # or Claude Code's worktree feature

# 2. From the canonical repo, make it ass-aware:
cd ~/Sync/mini_projects/agentstartstack   # or your host project canonical
ass discover --adopt     # or: ass adopt ~/.claude/worktrees/<name>
```

`ass adopt` writes `.agentstartstack.env` (derived from canonical), aligns the
worktree to canonical `main`, and readies it for agent work. Works for the
agentstartstack template repo itself (no `.agentstartstack.env` at canonical).

## Branding

Always lowercase **agentstartstack** in docs and messages (never Agent Start Stack / AgentStartStack).

## Maintenance

- CLI changes: edit `scripts/lib/ass-aliases.sh`, then re-run `scripts/install-shell-aliases.sh` and `source ~/.bashrc`
- Generic workflow changes belong here; bump the submodule in host projects when updated
- Project-specific gotchas, CLI, architecture stay in each host project's `docs/`