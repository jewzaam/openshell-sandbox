# Claude Agent Instructions

## Project Overview

OpenShell sandbox configuration for running Claude Code in auto mode inside
rootless Podman containers. Two profiles: home (Claude Max subscription) and
work (Vertex AI). Not a Python project — shell scripts, YAML policies, and a
Containerfile.

## Repository Layout

- `Containerfile` — sandbox image (python:3.13-slim base, installs Claude Code, node, uv, git)
- `Makefile` — `make build` (podman), `make clean`
- `bin/` — user scripts copied to `/sandbox/bin/` at image build time
- `config/bashrc` — base `.bashrc` baked into image, sources `/sandbox/.env`
- `policies/` — network + filesystem policies per profile (`home.yaml`, `work.yaml`)
- `policies/local.yaml` — gitignored, for custom overrides
- `scripts/sandbox.sh` — main entry point: create, upload, clone, start Claude
- `scripts/scode` — VS Code launcher for sandbox-backed sessions
- `scripts/mint-sandbox-token.py` — re-mint a single sandbox JWT using gateway signing key
- `scripts/mint-sandbox-tokens.sh` — wait for gateway, re-mint all errored sandbox JWTs
- `scripts/reset-rootless-netns.sh` — reset rootless podman network namespace after reboot/interface change
- `docs/troubleshooting.md` — known issues, triage, policy reference

## Key Concepts

- **Sandbox is the security boundary.** `--dangerously-skip-permissions` is
  intentional. Network policy (L4/L7), Landlock filesystem, and process
  isolation replace Claude's permission system.
- **Two-file env var split.** `.bashrc` is baked into the image (static).
  `.env` is written at sandbox creation (runtime credentials). `.bashrc`
  sources `.env`.
- **Profile auto-detection.** `CLAUDE_CODE_USE_VERTEX` set → work. Otherwise → home.
- **Symlink resolution.** `~/.claude/skills/` contains symlinks to `~/source/`
  repos. `rsync -rL` resolves them before upload so content works inside the sandbox.
- **settings.json stripping.** Allow permissions and hooks are removed from
  the uploaded settings.json. Deny permissions and marketplace config are kept.
- **Host-side repo management.** Repos are cloned on the host (where SSH
  works), then uploaded to the sandbox via `sandbox upload`. State tracked in
  `~/sandboxes/<name>/manifest.json`. Supports download (pull changes back),
  upload (push rebased code in), and add-repo (add to running sandbox).
- **Baked-in repos.** `knowledgebase` and `standards` are cloned at image build
  time into `/sandbox/source/`. Project repos are cloned on host and uploaded.
- **SSH→HTTPS URL auto-conversion.** Sandbox has no SSH egress (port 22 not in
  policy). `sandbox.sh` auto-converts `git@github.com:org/repo.git` to
  `https://github.com/org/repo.git` before cloning. Agents should pass either
  format — conversion is handled.
- **Containerfile HOME directory.** Use `useradd -d /sandbox` in Containerfile.
  Default HOME is `/home/sandbox`, causing gitconfig and env sourcing mismatches
  across `sandbox exec` calls. The `-d /sandbox` flag sets HOME correctly from passwd.

## OpenShell Policy Gotchas

These are hard-won — do not simplify or remove:

1. `binaries: [{ path: "*" }]` does NOT match all paths. Use `{ path: "/**" }`.
2. `access: write` is not valid. Valid: `read-only`, `read-write`, `full`. Invalid values silently deny.
3. `*.example.com` matches one subdomain level. Use `**.example.com` for multi-level.
4. `/sys` must be in `filesystem_policy.read_only` or `getifaddrs` fails (Node.js).
5. `sandbox connect` does not accept `-- COMMAND`. Use `sandbox exec --tty`.
6. `sandbox create` with `-- COMMAND` hangs on podman driver. Create in background, poll, use `exec`.
7. `--upload` on `sandbox create` is unreliable. Use `sandbox upload` after creation.
8. `sandbox upload` preserves symlinks as-is. Resolve with `rsync -rL` before uploading.
9. `sandbox exec` stdin pipe is limited to 4MB.
10. OpenShell overwrites `/sandbox/.bashrc` during `sandbox create`. Re-upload after creation.
11. `sandbox upload` treats destination as parent directory. Uploading `foo` to `/sandbox/` creates `/sandbox/foo/`.
12. `sandbox upload` of a single file to a directory replaces the directory contents. Upload the parent directory instead (e.g. `upload bin/ /sandbox/` not `upload bin/file /sandbox/bin/`).
13. All traffic goes through OpenShell's HTTP/1.1 CONNECT proxy. gRPC (HTTP/2) cannot traverse it. Use OTLP HTTP (`http/protobuf` on port 4318) instead of gRPC (port 4317) for telemetry.
14. Policies can be hot-updated on running sandboxes: `openshell policy set --policy <file> <name>`.
15. `github.com` requires `access: read-write` in network policy for HTTPS git clone. Git clone over HTTPS uses POST (`git-upload-pack`), not GET. `api.github.com` stays `read-only` to block REST API mutations (push, PR create).

## Reboot Recovery

After system reboot, two things break:

1. **Rootless-netns is stale.** Pasta's rootless network namespace references
   interfaces from the previous boot. Run `scripts/reset-rootless-netns.sh`
   before starting the gateway. This stops all containers, kills pasta,
   removes the netns dir, restarts podman socket, then restarts the containers.

2. **Sandbox JWTs are expired.** Tokens have a 1-hour TTL. After reboot +
   gateway restart, all existing sandbox tokens are stale. The supervisor
   inside each sandbox fails with `Unauthenticated: ExpiredSignature`.
   Run `scripts/mint-sandbox-token.py <name>` to write a fresh token to the
   bind-mounted host file, then restart the container.

The JWT claims structure must include `sandbox_id` (denormalized UUID) in
addition to the SPIFFE `sub` field — omitting it causes `missing field
sandbox_id` validation error. `iss` and `aud` must be
`openshell-gateway:<gateway_id>`, not just `openshell-gateway`.

## Shell Script Gotchas

- **`.env` newline loss.** Bash `$()` command substitution strips trailing
  newlines. When building `.env` content with `printf '%s=%q\n'` inside `$()`,
  the final newline is lost. Append `$'\n'` explicitly outside the substitution.

## Development Workflow

1. Edit files
2. `make build` if Containerfile, bin/, or config/ changed
3. Test with `scripts/sandbox.sh --create test`
4. No rebuild needed for policy-only or env var changes

## Standards

- Shell scripts: `set -euo pipefail`, no semicolons for chaining (use `&&`)
- Makefile: follows `~/source/standards/build/makefile.md` (verb-noun targets, self-documenting help)
- Naming: `~/source/standards/common/naming.md` (lowercase, hyphens)
- Local config: `~/source/standards/common/local-config-split.md` (`local.yaml` gitignored)
- Container tool: podman (not docker). `CONTAINER_TOOL ?= podman` in Makefile
- License: Apache 2.0
