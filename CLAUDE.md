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
- `config/repo-update.json` — repo list, installed to `/sandbox/.config/repo-update.json`
- `policies/` — network + filesystem policies per profile (`home.yaml`, `work.yaml`)
- `policies/local.yaml` — gitignored, for custom overrides
- `scripts/sandbox.sh` — main entry point: create, upload, clone, start Claude
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
- **Baked-in repos.** `knowledgebase` and `standards` are cloned at image build
  time into `/sandbox/source/`. Project repos are cloned at sandbox creation.
- **repo-update.json.** Installed to `/sandbox/.config/repo-update.json` at
  build time. Lists repos for update tooling.

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

## Development Workflow

1. Edit files
2. `make build` if Containerfile, bin/, or config/ changed
3. Test with `scripts/sandbox.sh --name test`
4. No rebuild needed for policy-only or env var changes

## Standards

- Shell scripts: `set -euo pipefail`, no semicolons for chaining (use `&&`)
- Makefile: follows `~/source/standards/build/makefile.md` (verb-noun targets, self-documenting help)
- Naming: `~/source/standards/common/naming.md` (lowercase, hyphens)
- Local config: `~/source/standards/common/local-config-split.md` (`local.yaml` gitignored)
- Container tool: podman (not docker). `CONTAINER_TOOL ?= podman` in Makefile
- License: Apache 2.0
