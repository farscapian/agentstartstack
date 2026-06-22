# Testing

Generic pre-handoff checklist. Host projects extend this in their own `agentstartstack/testing.md` with hardware-specific steps.

## Before human approval or nut

### Shell script validation

```bash
# Syntax check (adjust script list per project)
bash -n script1.sh script2.sh

# ShellCheck (see code-quality.md)
find . -name "*.sh" -type f ! -path "./.git/*" ! -path "./agentstartstack/*" -print0 | xargs -0 shellcheck -x
```

### Git hygiene

- [ ] No `.env` files staged in `git status`
- [ ] No backup archives or secrets in staged files
- [ ] No generated output with credentials committed

### Integration testing

Run against real hardware or infrastructure when the change affects:
- Device flash / serial / OTA
- Network provisioning / cloud-init
- Build pipelines that produce firmware images
- Long-running CLI workflows

**Safe without hardware:** `bash -n`, shellcheck, unit checks, compile-only paths, reading log files, editing templates in the session clone.

## Agent handoff notes

When committing before full integration test, note in the commit message:
- What was tested (unit / compile / hardware / none)
- Which paths are untested (e.g. TLS, nightly reprovision, edge-case devices)
- Any dependency on human running CLI from the canonical local repo