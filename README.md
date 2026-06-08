# openshell-sandbox

OpenShell sandbox configuration for running Claude Code in auto mode with full
SDLC skill access. Podman-based, rootless.

## Overview

- Sandboxed Claude Code execution — network policy is the security boundary, not
  Claude's permission system (`--dangerously-skip-permissions`)
- Two profiles: **home** (Claude Max / Anthropic direct) and **work** (Vertex AI + Jira)
- Auto-detects profile from env vars
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
sandbox.sh --create nexus --repo git@github.com:org/nexus.git --ref pr/42

# Create-or-connect (idempotent)
sandbox.sh --ensure nexus-pr-42 --repo git@github.com:org/nexus.git --ref pr/42

# Multiple repos
sandbox.sh --create nexus --repo git@github.com:org/nexus.git --repo git@github.com:org/nexus-ui.git

# Add repo to existing sandbox (infer URL from local checkout)
sandbox.sh --add-repo nexus --source-dir ~/source/lib

# Add repo with explicit URL
sandbox.sh --add-repo nexus --repo git@github.com:org/lib.git --ref v2.0

# Download changes from sandbox
sandbox.sh --download nexus

# Upload rebased code back into sandbox
sandbox.sh --upload nexus --repo nexus

# Reconnect to existing sandbox (launches Claude)
sandbox.sh --connect nexus

# List / delete
sandbox.sh --list
sandbox.sh --delete nexus
```

### Options

| Option | Description |
|--------|-------------|
| `--create NAME` | Create sandbox with this name |
| `--ensure [NAME]` | Create if missing, reconnect if exists |
| `--repo URL` | Git repo to clone on host and upload (repeatable) |
| `--ref REF` | Ref for preceding `--repo`: branch, `pr/<num>`, `tag/<name>`, or SHA |
| `--source-dir DIR` | Copy remotes from local repo and fetch (sandbox has no git auth) |
| `--add-repo [NAME]` | Add repo(s) to existing sandbox |
| `--download [NAME]` | Download repos from sandbox to `~/sandboxes/<name>/` |
| `--upload [NAME]` | Upload local repo changes back into sandbox |
| `--policy FILE` | Override policy file (default: auto-detect home/work) |
| `--gateway NAME` | OpenShell gateway |
| `--connect [NAME]` | Reconnect to existing sandbox (launches Claude) |
| `--delete [NAME]` | Delete sandbox and local state |
| `--no-clone` | Skip repo cloning |
| `--list` | List sandboxes |

`[NAME]` is optional when CWD is under `~/sandboxes/<name>/`.

### scode — VS Code launcher for sandboxes

```bash
# Open sandbox for a repo + ref (auto-names sandbox <repo>-<ref>)
scode ~/source/nexus pr/1176

# Default branch
scode ~/source/nexus

# Custom sandbox name, no repos (add repos separately)
scode --name review-workspace
```

Creates `~/sandboxes/<name>/.vscode/tasks.json` with auto-launching sandbox
and bash terminals, then opens VS Code.

### Profiles

| Profile | Auth | Network Access |
|---------|------|----------------|
| `home` | Claude Max subscription (login session) | Anthropic API, npm, PyPI |
| `work` | Vertex AI (`CLAUDE_CODE_USE_VERTEX`) | Google APIs, Jira, npm, PyPI |

Auto-detection: `CLAUDE_CODE_USE_VERTEX` set → work, otherwise → home.

## Layout

```
.
├── Containerfile           # Sandbox image
├── Makefile                # build, clean
├── bin/                    # Scripts copied to /sandbox/bin/ (on PATH)
├── config/
│   └── bashrc              # Base .bashrc (baked into image)
├── policies/
│   ├── home.yaml           # Anthropic direct
│   └── work.yaml           # Vertex AI + Jira
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
└── source/                 # Repos (baked + cloned at create time)
    ├── knowledgebase/      # Baked into image
    ├── standards/          # Baked into image
    ├── nexus/              # Uploaded from host
    └── nexus-ui/           # Uploaded from host
```

## Development

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
