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

```bash
# Create sandbox with repo at specific PR
sandbox.sh --create nexus --repo git@github.com:org/nexus.git --ref pr/42

# Multiple repos
sandbox.sh --create nexus --repo git@github.com:org/nexus.git --repo git@github.com:org/nexus-ui.git

# Add repo to existing sandbox
sandbox.sh --add-repo nexus --repo git@github.com:org/lib.git --ref v2.0

# Download changes from sandbox (run in second terminal)
sandbox.sh --download nexus

# Upload rebased code back into sandbox
sandbox.sh --upload nexus --repo nexus

# Reconnect to existing sandbox
sandbox.sh --connect nexus

# List / delete
sandbox.sh --list
sandbox.sh --delete nexus
```

### Options

| Option | Description |
|--------|-------------|
| `--create NAME` | Create sandbox with this name |
| `--repo URL` | Git repo to clone on host and upload (repeatable) |
| `--ref REF` | Ref for preceding `--repo`: branch, `pr/<num>`, `tag/<name>`, or SHA |
| `--add-repo NAME` | Add repo(s) to existing sandbox (use `--repo` for URL) |
| `--download NAME` | Download repos from sandbox to `~/sandboxes/<name>/` |
| `--upload NAME` | Upload local repo changes back into sandbox |
| `--policy FILE` | Override policy file (default: auto-detect home/work) |
| `--gateway NAME` | OpenShell gateway |
| `--connect NAME` | Reconnect to existing sandbox |
| `--delete NAME` | Delete sandbox and local state |
| `--no-clone` | Skip repo cloning |
| `--list` | List sandboxes |

### Profiles

| Profile | Auth | Network Access |
|---------|------|----------------|
| `home` | Claude Max subscription (login session) | Anthropic API, GitHub, npm, PyPI |
| `work` | Vertex AI (`CLAUDE_CODE_USE_VERTEX`) | Google APIs, Jira, GitHub, npm, PyPI |

Auto-detection: `CLAUDE_CODE_USE_VERTEX` set → work, otherwise → home.

## Layout

```
.
├── Containerfile           # Sandbox image
├── Makefile                # build, clean
├── bin/                    # Scripts copied to /sandbox/bin/ (on PATH)
├── config/
│   ├── bashrc              # Base .bashrc (baked into image)
│   └── repo-update.json    # Repo list for update tooling
├── policies/
│   ├── home.yaml           # Anthropic direct + GitHub
│   └── work.yaml           # Vertex AI + Jira + GitHub
├── scripts/
│   └── sandbox.sh          # Create/manage sandboxes
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
│   ├── gcloud/             # Uploaded from host (Vertex AI creds)
│   └── repo-update.json    # Repo list (baked into image)
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

## Documentation

- **[Troubleshooting](docs/troubleshooting.md)** — known issues, triage steps, policy reference
