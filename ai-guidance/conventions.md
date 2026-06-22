# Conventions

## Naming

**Always use lowercase for the project display name** (from `DISPLAY_NAME` in `.agentstartstack.env`). Examples:
- OK: `wrtstack build gw-wrt`
- OK: `iotstack flash matrixdisplay`
- BAD: ~~WrtStack~~, ~~IoT Stack~~, ~~PrintStack~~

This applies in code comments, documentation, help text, and all user-facing messages.

Script and hostname names may use their own historical conventions (`pi-bootstrap`, `usbproxy.printstack.local`) -- do not rename unless explicitly asked.

## ASCII-only text

**All documents, logging output, code comments, and help text must be ASCII-only.**

- No Unicode symbols: checkmarks, arrows, emoji, box-drawing, em dashes, etc.
- Use `--` instead of em dash, `->` instead of arrow, `[OK]`/`[FAIL]` instead of checkmarks
- Section dividers in shell comments: `# -- Title --` not box-drawing characters
- ANSI color escape bytes in `$'\033[...]'` variables are OK for terminal coloring; message text itself stays ASCII

Existing scripts may still contain Unicode box-drawing in comment headers; do not add more. Prefer `# --` for new sections.

Optional maintenance utility (if present in host project): `scripts/ascii-only-sanitize.py`.

## Script output

Runtime script output uses plain ASCII status tags:

- `[INFO]`, `[OK]`, `[WARN]`, `[ERR]`, `[FAIL]`
- Use `matches`, `!=`, `...` instead of decorative characters
- Progress: timestamped `log()` or `info()` lines -- no animated spinners

## Secrets on the CLI

**Never pass secrets as CLI arguments.** Passwords, API keys, and tokens belong in `.env` files (gitignored) or secret stores:

```bash
# OK: flags only, secrets in env file
sudo ./pi-bootstrap.sh --flash --force

# BAD: secrets on command line (visible in ps, history)
sudo ./pi-bootstrap.sh --wifi-password "secret"
```

See [security.md](security.md).

## Generated and ignored files

Common patterns across mini-projects:

| Track in git | Never track |
|--------------|-------------|
| `*.env.example`, scripts, templates | `*.env` (except examples), `cloud-init/*` output |
| `ai-guidance/`, `agentstartstack/` submodule pointer | Large binaries (`*.img`, `*.img.xz`) |
| Public config, package lists | Backup archives with secrets (`backups/**/*.tar.gz`) |