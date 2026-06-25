# Implementation Details

Common shell patterns used across projects. Project-specific logging paths and CLI behavior belong in host `docs/`.

### Env file loading pattern

```bash
# 1. Load shared.env (if present)
set +u
source "$SHARED_ENV"
set -u

# 2. Load node-specific .env
set +u
source "$ENV_FILE"
set -u

# 3. Apply defaults for optional vars
LAN_SUBNET="${LAN_SUBNET:-192.168.4.0/22}"
```

`set +u` before `source` prevents abort on unset optional variables. Required vars are validated explicitly after sourcing.

### Stdout/Stderr and user prompts

If a script redirects stdout to a log file, user prompts break:

```bash
exec > >(tee -a "$LOG_FILE") 2>&1
```

**Solution for prompts after redirect:**
```bash
echo "Continue?" >&2
read -r -p "Continue? [y/N] " confirm </dev/tty
```

Always use `</dev/tty` for interactive confirmation after any stdout redirect.

### Trap cleanup

```bash
cleanup() {
  if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then umount "$MOUNT_POINT" 2>/dev/null || true; fi
}
trap cleanup EXIT
```

Always release mounts, temp files, and background jobs before exit.

### YAML / heredoc indent builder variables

Cloud-init and config heredocs need correctly indented interpolated blocks. Build these in loops **before** the heredoc:

```bash
SSH_PUBKEYS_YAML=""
while IFS= read -r key; do
  [[ -z "${key// }" ]] && continue
  SSH_PUBKEYS_YAML+="      - ${key}"$'\n'
done <<< "$SSH_PUBKEYS"
```

Reference at column 0 inside the heredoc: `${SSH_PUBKEYS_YAML}`. The variable content carries its own indentation.

### Nested heredocs for conditional blocks

```bash
$(if [[ "$ENABLE_TLS" == "true" ]]; then cat <<TLS_EOF
  # TLS-specific lines
TLS_EOF
fi)
```

Keep inner heredoc delimiters unique (e.g. `TLS_EOF`, `META_EOF`).

### Temporary files

- Prefer `~/.<project>/artifacts/` or system temp dirs over cluttering the repo
- Clean up on exit via `trap`
- Name with PID suffix when concurrent runs are possible: `.temp-<purpose>-<PID>`