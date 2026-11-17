# openshell-sandbox

[![Test](https://github.com/jewzaam/openshell-sandbox/actions/workflows/test.yml/badge.svg)](https://github.com/jewzaam/openshell-sandbox/actions/workflows/test.yml) [![Quality](https://github.com/jewzaam/openshell-sandbox/actions/workflows/quality.yml/badge.svg)](https://github.com/jewzaam/openshell-sandbox/actions/workflows/quality.yml)

OpenShell sandbox configuration for running Claude Code in auto mode with full
SDLC skill access. Podman-based, rootless.

## Documentation

- **[Environment variables](docs/environment-variables.md)** — how a variable reaches a sandbox process
- **[Fetch service](docs/fetch-service.md)** — outbound fetch service for sessions inside a sandbox
- **[Troubleshooting](docs/troubleshooting.md)** — known issues, triage steps, policy reference
- **[Configuration model (draft)](docs/configuration-model.md)** — proposal only; not implemented

## Overview

- Sandboxed Claude Code execution — network policy is the security boundary, not
  Claude's permission system (`--dangerously-skip-permissions`)
- Three profiles: **work** (Vertex AI + Jira), **personal** (Anthropic direct,
  telemetry push-only), **home** (personal plus Prometheus/Loki reads)
- `--harness claude|codex|opencode` picks the agent. Claude is the default
  everywhere; Codex and OpenCode run on **work**, which carries OpenAI
  alongside Vertex. The profile never picks the agent. Extra provider profiles
  (Codex-format, also how Claude reaches `ANTHROPIC_BASE_URL`) must be
  explicitly bound to sandbox profiles with `PROVIDER_PROFILES_WORK`,
  `PROVIDER_PROFILES_PERSONAL`, or `PROVIDER_PROFILES_HOME` in gitignored
  `config/site.env`. Only each sandbox's authorized provider definitions,
  profile configs, model catalogs, keys, and endpoints are published. Unbound
  profiles never ship. Changed bindings require recreation, and old Codex
  session state is not restored across that boundary.
- `--profile` is required on `scode` and on `sandbox.sh --create/--recreate`
- Clones repos on host (SSH works), uploads to sandbox for private repo support
- Uploads `~/.claude/` config with symlinks resolved (skills, plugins, settings)
- `/sandbox/bin/` on PATH for arbitrary user scripts

## Installation

```bash
git clone <repo-url>
cd openshell-sandbox
make build
```

### Site configuration

`config/site.env` is per-machine and gitignored. Create it from the template
and fill in the telemetry endpoints for this host:

```bash
cp config/site.env.example config/site.env
```

`OTEL_URL`, `PROMETHEUS_URL`, and `LOKI_URL` are all required — there are no
defaults — and `sandbox.sh` refuses to run without them. The file is never
created automatically: the template's values are one site's, and adopting them
silently would point a sandbox at a collector that may not exist here. See the
comments in `config/site.env.example` for the expected forms and the optional
settings.

### Prerequisites

1. Podman 5.x with rootless support and cgroups v2
2. OpenShell CLI installed
3. OpenShell gateway running: `openshell gateway start --driver podman`
4. fzf, for the `--reap` picker (`--reap --all` runs without it)
5. A `claude-otel-stack` checkout for `OTEL_STACK_BIN` (default
   `~/source/claude-otel-stack/bin`); `make build` copies its `claude` and
   `codex` shims
6. The host managed-settings file for `MANAGED_SETTINGS_SRC` (default
   `/etc/claude-code/managed-settings.json`); the work image bakes it in

## Usage

### sandbox.sh — create and manage sandboxes

```bash
# Create sandbox with repo at specific PR
sandbox.sh --create myapp --profile work --repo git@github.com:org/myapp.git --ref pr/42

# Create-or-connect (idempotent)
sandbox.sh --ensure myapp-pr-42 --profile work --repo git@github.com:org/myapp.git --ref pr/42

# Multiple repos
sandbox.sh --create myapp --profile work --repo git@github.com:org/myapp.git --repo git@github.com:org/myapp-ui.git

# Add repo to existing sandbox (infer URL from local checkout)
sandbox.sh --add-repo myapp --source-dir ~/source/lib

# Add repo with explicit URL
sandbox.sh --add-repo myapp --repo git@github.com:org/lib.git --ref v2.0

# Add a repo with 30 days of history instead of all of it (uploads carry .git)
sandbox.sh --add-repo myapp --repo git@github.com:org/big.git --since -30days

# Download changes from sandbox
sandbox.sh --download myapp

# Upload rebased code back into sandbox
sandbox.sh --upload myapp --repo myapp

# Reconnect to existing sandbox (launches the selected harness)
sandbox.sh --connect myapp

# List / delete
sandbox.sh --list
sandbox.sh --delete myapp

# Rename the sandbox you are in (asks first; the container keeps running)
cd ~/sandboxes/myapp && sandbox.sh --rename myapp-v2

# Pick idle sandboxes to delete (stopped, orphaned directory, or orphaned container)
sandbox.sh --reap
sandbox.sh --reap --older-than 7 --dryrun
```

### Options

Common options below; `sandbox.sh --help` lists every one.

| Option | Description |
|--------|-------------|
| `--create NAME` | Create sandbox with this name (requires `--profile`) |
| `--ensure [NAME]` | Create if missing, reconnect if exists; use `--no-connect` to only create |
| `--repo URL` | Git repo to clone on host and upload (repeatable) |
| `--ref REF` | Ref for preceding `--repo`: branch, `pr/<num>`, `tag/<name>`, or SHA |
| `--source-dir DIR` | Copy remotes from local repo and fetch (sandbox has no git auth) |
| `--since DATE` | Clone only history newer than DATE, every repo in this run. Any `date -d` value (`-30days`, `-3months`, `2026-08-01`); `''` for full. Default: `SANDBOX_CLONE_SINCE` from `config/site.env` |
| `--add-repo [NAME]` | Add repo(s) to existing sandbox |
| `--jira KEY` | Fetch Jira issue into `~/sandboxes/<name>/jira-context.md` and its comments into `jira-comments.md`, from the sandbox directory (repeatable; key or browse URL). The keys given are the file; `--create`/`--refresh` upload both |
| `--download [NAME]` | Download repos from sandbox to `~/sandboxes/<name>/`. Plain runs pull only files changed in the sandbox and remove host files the sandbox no longer has; `--force` pulls the whole repo, `.git` and `.venv` included |
| `-f, --force` | With `--upload`/`--download`: transfer every repo in full and regenerate context. Plain runs transfer only what changed |
| `--upload [NAME]` | Upload local repo changes back into sandbox. Plain runs send only files newer than the last transfer and remove sandbox files the host no longer has; `--force` sends the whole repo, `.git` and `.venv` included |
| `--profile NAME` | `work`, `personal`, or `home`. Required with `--create` and `--recreate` |
| `--policy FILE` | Override policy file (default: the profile's own) |
| `--gateway NAME` | OpenShell gateway |
| `--connect [NAME]` | Reconnect to existing sandbox (launches the selected harness) |
| `--delete [NAME]` | Delete sandbox and local state |
| `--rename NEW` | From inside `~/sandboxes/<name>/`: confirm, move the directory to `NEW`, then `--refresh` it and connect (`--no-connect` stops after the refresh). No recreate: the container keeps running under its `sb-<hash>`, and the old name is free to reuse, since new sandboxes get a random openshell name. OTEL `project`/`sandbox.source` change for sessions started after the rename. A failed refresh stays pending for the next connect (`tests/test-rename.sh`) |
| `--reap` | Pick idle sandboxes to delete in fzf, then confirm. Offers a stopped container with its directory, a directory with no container, and an `sb-<hash>` container with no directory. Columns show dirty repos, stashes and unpushed commits in the host copy |
| `--older-than DAYS` | With `--reap`: idle threshold, default 30 |
| `--no-clone` | Skip repo cloning |
| `--list` | List sandboxes |

`[NAME]` is optional when CWD is under `~/sandboxes/<name>/`.

### scode — VS Code launcher for sandboxes

```bash
# Open sandbox for a repo + ref (auto-names sandbox <repo>-<ref>)
scode --profile work ~/source/myapp pr/1176

# Open a GitHub branch URL directly (branch slashes are supported)
scode https://github.com/org/myapp/tree/feature/my-branch --profile personal

# Default branch
scode --profile home ~/source/myapp

# Custom sandbox name, no repos (add repos separately)
scode --profile personal --name review-workspace

# Reopen an existing sandbox — --profile is required here too
scode --profile work ~/sandboxes/myapp-pr-1176
```

Creates `~/sandboxes/<name>/.vscode/tasks.json` with auto-launching sandbox
and bash terminals, then opens VS Code.

### Profiles

| Profile | Auth | Network Access |
|---------|------|----------------|
| `work` | Vertex AI (`CLAUDE_CODE_USE_VERTEX`) or a Claude provider via `ANTHROPIC_BASE_URL` (a private provider on this host), plus OpenAI for `--harness codex` (`/sandbox/.codex/auth.json`), OpenCode's host config with provider keys from `.env`, and explicitly bound Codex providers | Google APIs, Jira, OpenAI, bound Codex providers, npm, PyPI, Debian, Go modules, OTEL push, Prometheus + Loki reads |
| `personal` | Anthropic direct (API key or OAuth) | Anthropic API, npm, PyPI, Debian, Go modules, OTEL push only |
| `home` | Anthropic direct (API key or OAuth) | as `personal`, plus Prometheus + Loki reads |

`personal` and `home` may also receive explicitly bound custom Codex providers.
They never receive the host's OpenAI `auth.json` or work Codex configuration.

No default and no auto-detection: name the profile or the command refuses.
`scode` needs it on every invocation, reopening an existing sandbox included —
the profile decides which credentials leave the host.

Each profile is one word across three places: `policies/<profile>.yaml`, an
optional `config/sandbox-claude.d/<profile>.md` appended to the system prompt,
and `.profile` in the sandbox's `manifest.json`.

## Layout

```
.
├── Containerfile           # Sandbox image
├── Containerfile.work      # Work image, with managed-settings deny list baked in
├── Makefile                # build, check/test, clean
├── bin/                    # Scripts copied to /sandbox/bin/ (on PATH)
├── config/
│   ├── bashrc              # Base .bashrc (baked into image)
│   ├── sandbox-claude.md   # System prompt, every profile
│   ├── sandbox-claude.d/   # Per-profile additions, appended to the above
│   └── site.env.example    # Per-machine telemetry endpoints (copy to site.env)
├── fetchsvc/
│   ├── Containerfile       # Fetch-service image
│   ├── fetch_service.py    # Outbound fetch service
│   └── fetchsvc.sh         # Build/start/stop the container
├── policies/
│   ├── work.yaml           # Vertex AI + Jira
│   ├── personal.yaml       # Anthropic direct, telemetry push-only
│   ├── home.yaml           # personal + Prometheus/Loki reads
│   ├── research.yaml       # research policy, used with --policy
│   └── fetch-service.yaml  # personal + outbound fetch service
├── scripts/
│   ├── sandbox.sh              # Create/manage sandboxes
│   ├── scode                   # VS Code launcher for sandboxes
│   ├── mint-sandbox-token.py   # Re-mint a single sandbox JWT
│   ├── mint-sandbox-tokens.sh  # Re-mint all errored sandbox JWTs
│   └── reset-rootless-netns.sh # Reset rootless podman networking
├── tests/                  # Shell self-checks (make test-unit)
└── docs/
    ├── configuration-model.md  # Draft proposal, not implemented
    ├── environment-variables.md # How a variable reaches a sandbox process
    ├── fetch-service.md      # Fetch service, for sessions inside a sandbox
    └── troubleshooting.md    # Known issues and fixes
```

### Sandbox filesystem

```
/sandbox/
├── .bashrc                 # Sources .env, sets PATH
├── .env                    # Runtime env vars (generated at create time)
├── .claude/                # Uploaded from host (symlinks resolved)
├── .config/
│   ├── gcloud/             # Uploaded from host (Vertex AI creds)
│   └── opencode/           # Host config + theme; host boundaries dropped
├── .local/
│   └── state/opencode/     # Host's selected model (model.json)
├── bin/                    # User scripts (from repo bin/)
└── source/                 # Cloned on host, uploaded at create time
    ├── CLAUDE.md           # System prompt (from config/sandbox-claude.md)
    ├── manifest.json       # Sandbox name, repo list, profile
    ├── openshell-policy.yaml  # Effective policy, rendered from site.env
    ├── files/              # Loose transfer dir, not a repo (see below)
    ├── knowledgebase/      # Uploaded from host
    ├── standards/          # Uploaded from host
    ├── myapp/              # Uploaded from host
    └── myapp-ui/           # Uploaded from host
```

`/sandbox/source/files/` is a transfer directory for loose files — notes, data,
output — that do not belong to a repo. The host side is
`~/sandboxes/<name>/files/`, created at create time. Both `sandbox.sh --upload`
and `--download` always include it, so files move in either direction without
`--add-repo`. An empty host copy is never uploaded: sending it would empty the
sandbox-side directory.

## Development

### Checks

```bash
make check        # shellcheck + self-checks — the default goal
make test-lint    # shellcheck, warnings and up
make test-unit    # the tests/ self-checks
```

CI runs the same two targets on every push and PR to `main` (`quality` and
`test`). `make test-lint` needs `shellcheck`; nothing else needs installing.

### Adding scripts

Put scripts in `bin/`. They are copied to `/sandbox/bin/` at image build time
and are on `PATH` automatically.

### Custom policy

Copy a profile to `policies/local.yaml` (gitignored), edit, pass `--policy policies/local.yaml`.

### Rebuilding

```bash
make build
```

Rebuild when: bin/ scripts change, Containerfile changes, config/ changes.
No rebuild needed for: policy changes, env var changes, repo changes.

## After Reboot / Gateway Restart

Rootless Podman sandboxes need two recovery steps after a system reboot:

### 1. Reset the rootless network namespace

Pasta's rootless-netns becomes stale after reboot. Reset it before starting
the gateway:

```bash
scripts/reset-rootless-netns.sh
```

### 2. Re-mint sandbox JWTs

The gateway mints sandbox tokens with no expiry (`exp=0`), so new sandboxes
need nothing after a reboot or gateway restart. Sandboxes created before that
behavior may still hold a stale token; re-mint those.

```bash
# All errored sandboxes (waits for gateway, then re-mints + restarts)
scripts/mint-sandbox-tokens.sh

# Single sandbox — pass the openshell name (sb-<12 hex>), not the human
# sandbox name. The script stops the container, replaces the token, and
# starts it again.
python3 scripts/mint-sandbox-token.py "$(jq -r .openshell_name ~/sandboxes/<name>/manifest.json)"
```
