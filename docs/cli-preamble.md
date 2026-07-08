# CLI preamble (per-invocation hygiene for consumer CLIs)

Every consumer that ships a shell CLI (iotstack, printstack, wrtstack, ...) SHALL
invoke the shared preamble `scripts/cli-preamble.sh` (from the `.agentstartstack`
submodule) once at the top of `main()`, before it dispatches a subcommand. The
preamble centralizes per-invocation setup that must be identical across every
consumer -- working-tree hygiene now, worktree management and command hooks later.

Load this with [cli-conventions.md](cli-conventions.md) when building or extending
a project CLI. Language: **SHALL** = required; **SHOULD** = strong default.

## Scope: canonical repos only (SHALL)

This functionality is intended **only** for a human (or the `ass` CLI) operating
on a **canonical consumer repo**. It is a strict **no-op inside an agent session
clone/worktree** -- auto-committing there would create commits that fight session
alignment (canonical always wins; see [workflow.md](workflow.md)). The preamble
detects a clone via any of: the repo living under an `AGENT_SESSION_CLONE_PARENT`
(`~/.claude/worktrees` / `~/.grok/worktrees`); a `.agentstartstack.env` whose
`CANONICAL_LOCAL_REPO` names some other path; or an `agentstartstack-session-init`
marker in its git dir. In a clone it prints HEAD and returns without side effects.

## Responsibility 1: working-tree hygiene (SHALL)

If the canonical repo is dirty when the CLI runs, the preamble **auto-commits the
working tree** so that `GIT HEAD` documents the **exact** code about to run -- a
reproducible provenance stamp the CLI can record for troubleshooting.

- **Stashing is deliberately not used.** A stash hides the running code from HEAD,
  defeating the point. The committed state *is* the documentation.
- **Auto-commits are self-identifying.** Each carries a trailer so it is trivially
  greppable and can be discarded or squashed later to keep history tidy:

  ```bash
  git log --grep '^Agentstartstack-Autocommit:'
  ```

- **Contract.** The script prints **shell code to stdout for the caller to
  `eval`** -- after the eval the caller has `$AGENTSTARTSTACK_CLI_HEAD` (the HEAD
  SHA to record) and, when undo is configured, a self-registered EXIT trap. stdout
  is strictly `KEY=val` / `trap` lines; stderr is human diagnostics; exit is always
  0 -- the preamble never blocks the CLI. On a clean tree it just emits HEAD.

### Why eval (single static consumer stub)

`eval "$(script)"` runs the script's stdout in the CLI's own shell -- the only way
a child can set a variable and register a trap in the parent. That lets **all
policy live in agentstartstack**: the consumer's wiring is one line that never
changes, and persist-vs-undo, trap mechanics, and future preamble responsibilities
evolve here and reach consumers via the bump. It is the eval-a-hook idiom
(`ssh-agent`, `direnv`, `dircolors`): safe because the script is first-party at the
CLI's own trust level and its stdout is kept inert on every path (all diagnostics
go to stderr).

### Persist vs undo

Policy is set by env or, preferably, `<repo>/.agentstartstack.env` -- **never** in
the consumer CLI file (env wins over the file):

| Mode | Configure | Behavior |
|------|-----------|----------|
| **Persist** (default) | nothing | The auto-commit stays. HEAD permanently documents the run; clean up later via the grep above. |
| **Undo** (opt-in) | `AGENTSTARTSTACK_CLI_AUTOCOMMIT_UNDO=1` (env or `.agentstartstack.env`) | The auto-commit exists **during** the run (HEAD documents the exact code), then the self-registered `cli-postamble.sh` EXIT trap peels it back with a soft reset when the command completes -- restoring the uncommitted working tree. Stash/pop semantics done through a commit, with a valid HEAD mid-run. |

Undo is safe: `cli-postamble.sh` is a no-op unless the preamble left restore-state,
and it only resets when HEAD is still exactly the auto-commit (if the CLI made
further commits it leaves history alone). Tradeoff: with undo, the provenance SHA
is ephemeral -- valid for tools that snapshot/build against it during the run, but
not kept in history.

## Wiring (SHALL)

The **entire, permanently static** wiring -- one line near the top of `main()`,
after global-flag parsing, before command dispatch:

```bash
eval "$(AGENTSTARTSTACK_CLI_TOOL=<project> \
  "${REPO_ROOT}/.agentstartstack/scripts/cli-preamble.sh" "$REPO_ROOT")"
```

After it, record `$AGENTSTARTSTACK_CLI_HEAD` wherever the CLI documents run
provenance (log header, `--json` output, build metadata). Switching persist/undo,
or any later change to preamble behavior, is done in `.agentstartstack.env` or
inside agentstartstack -- the consumer line above is never edited again.

## Env toggles

| Variable | Effect |
|----------|--------|
| `AGENTSTARTSTACK_CLI_TOOL` | Label folded into the auto-commit subject/trailer (set to `<project>`). |
| `AGENTSTARTSTACK_CLI_PREAMBLE=0` | Disable the preamble entirely (still prints current HEAD; no side effects). |
| `AGENTSTARTSTACK_CLI_AUTOCOMMIT=0` | Run the dirty check but do not commit; warn on a dirty tree instead. |
| `AGENTSTARTSTACK_CLI_AUTOCOMMIT_UNDO=1` | Arm the self-registered `cli-postamble.sh` peel-back trap (see undo mode). |

Each toggle is read from the environment first, then from `<repo>/.agentstartstack.env`
(same key name), so policy can live in repo config rather than the consumer CLI.

## Extension points (reserved)

`cli-preamble.sh` marks two future responsibilities the user asked it to grow into
-- **worktree management** (session-worktree adoption/alignment; see
[`scripts/lib/session-clones.sh`](../scripts/lib/session-clones.sh)) and shared
**command hooks**. They are stubbed, not yet wired; add them there when specified,
keeping each fast and non-fatal so the preamble never blocks the CLI.

## Implementation

- Preamble: [`scripts/cli-preamble.sh`](../scripts/cli-preamble.sh)
- Undo trap: [`scripts/cli-postamble.sh`](../scripts/cli-postamble.sh)

See also: [cli-conventions.md](cli-conventions.md) (CLI structure/flags),
[workflow.md](workflow.md) (canonical vs session clones), [conventions.md](conventions.md)
(output tags, ASCII), [code-quality.md](code-quality.md) (shellcheck).
