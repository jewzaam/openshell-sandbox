# Troubleshooting

## Network Policy

### `curl: (56) Received HTTP code 403 from proxy after CONNECT`

Sandbox proxy blocked the connection. Endpoint not in policy.

**Triage:**
```bash
openshell logs <sandbox> --since 5m
```

Look for `NET:OPEN [MED] DENIED` lines — they show the host, port, and binary that was blocked.

**Fix:** Add the endpoint to your policy, recreate the sandbox.

### `POST /token not permitted by policy`

L7 proxy blocking an HTTP method.

**Cause:** `access: write` is not a valid value. Valid values: `read-only`, `read-write`, `full`. Invalid values silently deny everything.

**Fix:** Change `access: write` to `access: full` (or `read-write` if DELETE should be blocked).

### Binary not allowed in policy

```
binary '/usr/local/bin/claude' not allowed in policy 'vertex_ai'
```

**Cause:** `binaries: [{ path: "*" }]` does not match all paths. `*` matches one path segment only.

**Fix:** Use `{ path: "/**" }` for catch-all. `**` matches across path segments.

### Multi-level subdomain not matched

`*.googleapis.com` matches `oauth2.googleapis.com` but NOT `us-east5-aiplatform.googleapis.com`.

**Fix:** Use `**.googleapis.com` for multi-level subdomain matching.

## Authentication

### `Not logged in · Please run /login`

Claude Code cannot find credentials.

**Triage:**
1. Check env vars inside sandbox: `env | grep -E 'CLAUDE|VERTEX|ANTHROPIC'`
2. Check if gcloud creds exist: `ls /sandbox/.config/gcloud/`
3. Check if `.env` was written: `cat /sandbox/.env`

**Common causes:**
- `~/.config/gcloud/` uploaded with wrong nesting (extra `gcloud/` dir)
- `GOOGLE_APPLICATION_CREDENTIALS` points to a path that doesn't exist in sandbox
- Env vars not in `.env` because they weren't set in the host shell

### `getifaddrs returned an error`

Node.js cannot enumerate network interfaces.

**Cause:** `/sys` not in Landlock `read_only` paths.

**Fix:** Add `/sys` to `filesystem_policy.read_only` in your policy YAML.

### `Could not refresh access token: policy_denied`

OAuth token refresh POST blocked by L7 proxy.

**Triage:** Check `openshell logs <sandbox> --since 2m` for `HTTP:POST [MED] DENIED` entries.

**Fix:** Ensure `oauth2.googleapis.com` endpoint has `access: full` (not `write` or `read-only`).

## Sandbox Lifecycle

### `sandbox create` hangs at "Requesting sandbox..."

CLI's SSH connection during `sandbox create` doesn't establish on podman driver. The sandbox IS created — the hang is the CLI trying to connect.

**Workaround:** `sandbox.sh` handles this by running create in background, polling `sandbox list`, then using `sandbox exec`.

**Manual workaround:** Ctrl+C, then `openshell sandbox connect <name>`.

### `--upload` flag doesn't deliver files

Files uploaded via `--upload` on `sandbox create` may not appear in the sandbox.

**Workaround:** Use `openshell sandbox upload <name> <path> <dest>` after creation instead.

### `sandbox connect` doesn't accept commands

`connect` opens an interactive shell. It doesn't take `-- COMMAND`.

**Fix:** Use `openshell sandbox exec --name <name> --tty -- <command>`.

### `stdin payload exceeds 4194304 byte limit`

Piping data through `sandbox exec` is limited to 4MB.

**Fix:** Use `openshell sandbox upload` for large payloads.

### `~/.claude/` symlinks broken in sandbox

`sandbox upload` preserves symlinks as-is. Host paths don't exist in sandbox.

**Fix:** `sandbox.sh` uses `rsync -rL` to resolve symlinks before uploading.

## Policy Reference

### Valid `access` values

| Value | REST methods allowed |
|-------|---------------------|
| `read-only` | GET, HEAD, OPTIONS |
| `read-write` | GET, HEAD, OPTIONS, POST, PUT, PATCH |
| `full` | All methods including DELETE |

### Binary glob patterns

| Pattern | Matches |
|---------|---------|
| `/usr/bin/curl` | Exact path only |
| `/usr/local/bin/*` | Any file in that directory |
| `/usr/bin/python*` | python, python3, python3.11 |
| `/**` | Any binary anywhere |
| `/sandbox/.vscode-server/**` | Any binary in tree |

### Host wildcards

| Pattern | Matches |
|---------|---------|
| `api.github.com` | Exact host |
| `*.example.com` | One subdomain level (api.example.com) |
| `**.example.com` | Any subdomain depth (a.b.example.com) |
