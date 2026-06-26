# Security

## CRITICAL: Never print passwords or secrets

**Rule: NEVER echo passwords, API keys, or secrets to stdout/stderr**

Secrets printed to console can be captured in:
- Shell history (`~/.bash_history`, `~/.zsh_history`)
- Log files (CI logs, audit logs, syslog)
- Terminal session recordings
- Process monitoring tools (`ps`, `top`)
- `set -x` debug traces (bash prints expanded variables)

**Correct pattern:** secrets stay in `.env` files or secret stores, sourced by scripts

```bash
# OK: password in env file, sourced by script
# my-project.env:
WIFI_PASSWORD=actual_password

# FAIL: password on command line (visible in ps, history)
./bootstrap.sh --wifi-password "actual_password"

# FAIL: password echoed in script output
echo "WiFi password: $WIFI_PASSWORD"
```

**In code:**
- OK: `echo "[OK] WiFi configured from env file"`
- FAIL: `echo "[OK] WiFi password: $WIFI_PASSWORD"`
- OK: `echo "[OK] API key configured"`
- FAIL: `echo "[OK] API key: $NAMECHEAP_API_KEY"`

## .env file permissions

Bootstrap scripts should warn if `.env` files are world-readable. Recommend `chmod 600`:

```bash
chmod 600 *.env
```

## Git hygiene

| Track in git | Never track |
|--------------|-------------|
| `*.env.example` | Live `*.env` files |
| Scripts, templates | Generated runtime output with secrets |
| Public keys in config (when intentional) | Backup archives that may contain PSKs or VPN keys |

## pass password handling (when using `pass`)

**When using `pass insert` to store secrets, ALWAYS echo the password TWICE** (for confirmation):

```bash
# OK: password echoed twice
{ echo "$password"; echo "$password"; } | pass insert -f "project/path/secret"

# FAIL: password only echoed once (WILL FAIL SILENTLY)
echo "$password" | pass insert -f "project/path/secret"
```

**Why:** `pass insert` requires confirmation like interactive entry. Single echo fails silently (exit 1), causing repeated sync warnings and hours of debugging.

## Agent rules

- Never commit `.env` files, backup tarballs with secrets, or generated files containing credentials
- Never suggest `git add` on gitignored secret paths
- Redact secrets in commit messages and chat output