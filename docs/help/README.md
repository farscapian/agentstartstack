# ass command help files

Terminal help for the `ass` CLI. Each `.txt` file is shown by `ass <topic> help`
(or `ass help <topic>`). Edit these files to change what users see in the shell.

Structure and naming rules: [docs/cli-help.md](../cli-help.md).

## Files

- **ass.txt** -- main menu (direct subcommands only)
- **ass-sync.txt** -- local-sync handoff
- **ass-sync-all.txt** -- align all session clones behind canonical
- **ass-adopt.txt** -- make an agent-created worktree ass-aware
- **ass-discover.txt** -- list agent worktrees + adopt status
- **ass-list.txt** -- list session worktrees
- **ass-status.txt** -- ahead/behind report
- **ass-info.txt** -- plain-language session summary by index
- **ass-drop.txt** -- collapse to one clone, archive by index, or copy work upstream
- **ass-up.txt** -- handoff + push origin main
- **ass-up-trim.txt** -- consolidate and prune stale clones
- **ass-publish.txt** -- publish agentstartstack and bump .agentstartstack in consumers

## Usage

```bash
ass help
ass sync help
ass help up trim
cat docs/help/ass-sync.txt
```

Workflow and policy (not duplicated here): [docs/ass.md](../ass.md).