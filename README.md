# openshell-sandbox

OpenShell sandbox configuration for running Claude Code in auto mode with full
SDLC skill access. Podman-based, rootless.

## Overview

- Sandboxed Claude Code execution — network policy is the security boundary, not
  Claude's permission system (`--dangerously-skip-permissions`)
- Four profiles: **work** (Vertex AI + Jira), **personal** (Anthropic direct,
  telemetry push-only), **home** (personal plus Prometheus/Loki reads),
  **codex** (home with OpenAI in place of Anthropic — the agent is Codex CLI)
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

### Prerequisites

1. Podman 5.x with rootless support and cgroups v2
2. OpenShell CLI installed
3. OpenShell gateway running: `openshell gateway start --driver podman`

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

# Download changes from sandbox
sandbox.sh --download myapp

# Upload rebased code back into sandbox
sandbox.sh --upload myapp --repo myapp

# Reconnect to existing sandbox (launches Claude)
sandbox.sh --connect myapp

# List / delete
sandbox.sh --list
sandbox.sh --delete myapp
```

### Options

| Option | Description |
|--------|-------------|
| `--create NAME` | Create sandbox with this name (requires `--profile`) |
| `--ensure [NAME]` | Create if missing, reconnect if exists |
| `--repo URL` | Git repo to clone on host and upload (repeatable) |
| `--ref REF` | Ref for preceding `--repo`: branch, `pr/<num>`, `tag/<name>`, or SHA |
| `--source-dir DIR` | Copy remotes from local repo and fetch (sandbox has no git auth) |
| `--add-repo [NAME]` | Add repo(s) to existing sandbox |
| `--download [NAME]` | Download repos from sandbox to `~/sandboxes/<name>/` |
| `-f, --force` | With `--upload`/`--download`: transfer every repo and regenerate context. Plain runs transfer only what changed |
| `--upload [NAME]` | Upload local repo changes back into sandbox |
| `--profile NAME` | `work`, `personal`, `home`, or `codex`. Required with `--create` and `--recreate` |
| `--policy FILE` | Override policy file (default: the profile's own) |
| `--gateway NAME` | OpenShell gateway |
| `--connect [NAME]` | Reconnect to existing sandbox (launches Claude) |
| `--delete [NAME]` | Delete sandbox and local state |
| `--no-clone` | Skip repo cloning |
| `--list` | List sandboxes |

`[NAME]` is optional when CWD is under `~/sandboxes/<name>/`.

### scode — VS Code launcher for sandboxes

```bash
# Open sandbox for a repo + ref (auto-names sandbox <repo>-<ref>)
scode --profile work ~/source/myapp pr/1176

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
| `work` | Vertex AI (`CLAUDE_CODE_USE_VERTEX`) | Google APIs, Jira, npm, PyPI, OTEL push, Prometheus + Loki reads |
| `personal` | Anthropic direct (API key or OAuth) | Anthropic API, npm, PyPI, Debian, OTEL push only |
| `home` | Anthropic direct (API key or OAuth) | as `personal`, plus Prometheus + Loki reads |
| `codex` | OpenAI via `codex login` (`/sandbox/.codex/auth.json`) | as `home`, with OpenAI in place of Anthropic |

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
├── Makefile                # build, clean
├── bin/                    # Scripts copied to /sandbox/bin/ (on PATH)
├── config/
│   ├── bashrc              # Base .bashrc (baked into image)
│   ├── sandbox-claude.md   # System prompt, every profile
│   └── sandbox-claude.d/   # Per-profile additions, appended to the above
├── policies/
│   ├── work.yaml           # Vertex AI + Jira
│   ├── personal.yaml       # Anthropic direct, telemetry push-only
│   ├── home.yaml           # personal + Prometheus/Loki reads
│   └── codex.yaml          # home, OpenAI instead of Anthropic
├── scripts/
│   ├── sandbox.sh              # Create/manage sandboxes
│   ├── scode                   # VS Code launcher for sandboxes
│   ├── mint-sandbox-token.py   # Re-mint a single sandbox JWT
│   ├── mint-sandbox-tokens.sh  # Re-mint all errored sandbox JWTs
│   └── reset-rootless-netns.sh # Reset rootless podman networking
└── docs/
    └── troubleshooting.md  # Known issues and fixes
```

### Sandbox filesystem

```
/sandbox/
├── .bashrc                 # Sources .env, sets PATH
├── .env                    # Runtime env vars (generated at create time)
├── .claude/                # Uploaded from host (symlinks resolved)
├── .config/
│   └── gcloud/             # Uploaded from host (Vertex AI creds)
├── bin/                    # User scripts (from repo bin/)
└── source/                 # Cloned on host, uploaded at create time
    ├── CLAUDE.md           # System prompt (from config/sandbox-claude.md)
    ├── manifest.json       # Sandbox name, repo list, profile
    ├── openshell-policy.yaml  # Effective policy, rendered from site.env
    ├── knowledgebase/      # Uploaded from host
    ├── standards/          # Uploaded from host
    ├── myapp/              # Uploaded from host
    └── myapp-ui/           # Uploaded from host
```

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

Sandbox tokens expire after 1 hour (gateway-configured TTL). After a gateway
restart, existing sandboxes have stale tokens.

```bash
# All errored sandboxes (waits for gateway, then re-mints + restarts)
scripts/mint-sandbox-tokens.sh

# Single sandbox
python3 scripts/mint-sandbox-token.py <sandbox-name>
podman stop openshell-sandbox-<name> && podman start openshell-sandbox-<name>
```

## Documentation

- **[Troubleshooting](docs/troubleshooting.md)** — known issues, triage steps, policy reference
