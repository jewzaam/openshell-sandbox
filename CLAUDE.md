# Claude Agent Instructions

## Project Overview

OpenShell sandbox configuration for running Claude Code in auto mode inside
rootless Podman containers. One default profile (`code`), plus `research` for
web access. Not a Python project — shell scripts, YAML policies, and a
Containerfile.

## Repository Layout

- `Containerfile` — sandbox image (python:3.13-slim base, installs Claude Code, node, uv, git)
- `Makefile` — `make build` (podman), `make clean`
- `bin/` — user scripts copied to `/sandbox/bin/` at image build time
- `config/bashrc` — base `.bashrc` baked into image, sources `/sandbox/.env`
- `config/sandbox-claude.md` — sandbox system prompt, uploaded to `/sandbox/source/CLAUDE.md`
- `policies/` — network + filesystem policies per profile
- `policies/code.yaml` — default profile (work: Vertex AI + Jira + OTEL + observability)
- `policies/research.yaml` — web access profile (Claude platform, no Jira)
- `policies/personal.yaml` — personal profile (Anthropic API, no Vertex/Jira/gcloud, OTEL push-only)
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
- **Symlink resolution.** `~/.claude/skills/` contains symlinks to `~/source/`
  repos. `rsync -rL` resolves them before upload so content works inside the sandbox.
- **settings.json stripping.** Allow permissions nested under `permissions.allow`
  dict are removed from uploaded settings.json. Only OTEL dummy hooks
  (`python3 -c ""`) are preserved; all others stripped. Deny permissions and
  marketplace config are kept. The dummy hooks are critical — without a
  registered hook, Claude Code does not emit OTEL events for that hook type.
  The dummy hooks exist solely to trigger OTEL telemetry.
- **Host-side repo management.** Repos are cloned on the host (where SSH
  works), then uploaded to the sandbox via `sandbox upload`. State tracked in
  `~/sandboxes/<name>/manifest.json`. Supports download (pull changes back),
  upload (push rebased code in), and add-repo (add to running sandbox).
- **No baked-in repos.** All repos (including `knowledgebase` and `standards`)
  are cloned on the host and uploaded. Nothing is baked into the image.
- **Host-side git operations only.** Sandbox has no GitHub network access and
  no git authentication. All repos are pre-cloned on host.
- **Containerfile HOME directory.** Use `useradd -d /sandbox` in Containerfile.
  Default HOME is `/home/sandbox`, causing gitconfig and env sourcing mismatches
  across `sandbox exec` calls. The `-d /sandbox` flag sets HOME correctly from passwd.
- **`--ensure` (create-or-connect).** Checks if sandbox exists via `openshell sandbox list`,
  creates if missing (delegates to `--create`), reconnects if exists. Name can
  be inferred from CWD under `~/sandboxes/<name>/`.
- **`--refresh` (re-upload config).** Re-uploads `~/.claude/`, `bin/`, `.bashrc`,
  `.env`, and system prompt without recreating sandbox. Generates and uploads
  `pr-context.md` for PR-based repos. Validates gws credentials (interactive,
  runs first so browser prompt appears while user is present). Does not touch repos.
- **`--policy` hot-swap.** Standalone `--policy NAME` sets policy on running
  sandbox. Bare names resolve to `policies/<name>.yaml`. Validates async — polls
  `openshell policy list` for Loaded/Effective/Failed status.
- **`--source-dir` origin derivation.** Derives origin URL from local checkout
  when `--repo` is not specified. Does not copy additional remotes — sandbox
  gets only the origin remote from the fresh clone.
- **`.venv` exclusion.** Upload: rsync excludes `.venv` from `~/.claude/` upload.
  Download: downloads to staging dir, rsyncs to target with `--exclude=.venv`.
  Prevents Python version mismatch (host 3.14 vs sandbox 3.13).
- **Sandbox system prompt.** `config/sandbox-claude.md` uploaded as
  `/sandbox/source/CLAUDE.md`. Documents constraints (no GitHub, no SSH, no git
  auth). Startup instructions tell sessions to: (1) read `manifest.json` if
  present, (2) read every repo's `CLAUDE.md`, (3) auto-cd into single repo,
  (4) infer primary repo from user's first message using sandbox name and first
  repo in manifest as signals — only ask if truly ambiguous.
- **Keepalive.** Background process sends ENQ (`\005`) to stdout every 30s to
  prevent gRPC idle stream reaping.
- **`upload_config()` function.** Extracted upload logic (claude config, bin/,
  bashrc, env, system prompt) into reusable function called by `--create` and
  `--refresh`. Takes a second `sandbox_dir` parameter. Also uploads
  `manifest.json` to `/sandbox/source/manifest.json` so sandbox sessions know
  the sandbox name, repo list, and which repo was added first. Uses staged
  directory upload to avoid single-file tar gotcha (#12).
- **`upload_repo()` pre-delete on re-upload.** Deletes existing sandbox copy
  (`rm -rf /sandbox/source/<repo>`) before uploading to avoid tar type conflicts.
  Symlinks are preserved as-is (no `rsync -rL`). Without pre-delete, re-uploading
  a repo where a path changed between symlink and directory causes tar "Cannot
  open: File exists" failures.
- **`SANDBOX_JIRA_*` env var override.** `sandbox.sh` supports sandbox-specific
  scoped Jira credentials via separate env vars. When `SANDBOX_JIRA_TOKEN` is
  set, `sandbox.sh` overrides `JIRA_TOKEN`, `JIRA_API_TOKEN`, `JIRA_EMAIL`,
  `JIRA_USERNAME`, `JIRA_URL`, and `JIRA_CLOUD_ID` in the sandbox `.env` with
  values from `SANDBOX_JIRA_TOKEN`, `SANDBOX_JIRA_EMAIL`, `SANDBOX_JIRA_URL`,
  and `SANDBOX_JIRA_CLOUD_ID`. Last-value-wins when `.env` is sourced. Enables
  read-only scoped Atlassian tokens in sandboxes while host keeps broad credentials.
- **`--profile` credential profiles.** `--profile <name>` controls which env
  var groups, credential uploads, and default policy a sandbox gets. Stored in
  `manifest.json` so `--refresh` inherits it. Profile `personal` uses
  `ANTHROPIC_API_KEY` (subscription, not Vertex), skips JIRA/gcloud/gws
  credentials, defaults to `policies/personal.yaml`, strips Jira and
  Prometheus/Loki sections from sandbox system prompt, and disables OTEL
  entirely. No profile (default) = current behavior.
- **Personal profile has no OTEL.** OpenShell cannot selectively block ports
  on `host.containers.internal` — the container gateway host is implicitly
  allowed on all ports regardless of policy. This means a personal sandbox
  with OTEL collector access (port 4318) can also reach Prometheus (9090)
  and Loki (3100), which contain work session telemetry. To prevent work
  data leakage, personal profile skips OTEL entirely: no OTEL env vars
  captured, `claude.env` not sourced in `claude-wrapper.sh`, and OTEL
  collector removed from `personal.yaml`. `validate-profile.sh` documents
  the gap — `host.containers.internal` ports show FAIL because they're
  reachable despite not being in policy.
- **dtach session persistence.** `claude-wrapper.sh` uses dtach for raw
  PTY session persistence (no terminal emulation layer). Socket at
  `/sandbox/.dtach-claude`. On connect, if socket exists, default command
  is `dtach -a /sandbox/.dtach-claude` (reattach). Reconnecting reattaches
  to the running Claude process — no new launch, no context reload, no
  token burn. Detach key: `Ctrl+\`. Requires `/dev/pts` in policy
  `read_write` (added to all three policy YAML files). screen and tmux
  were evaluated and rejected — both mangle Claude Code's TUI rendering
  through their terminal emulation layers. See
  `knowledgebase/containers/terminal-multiplexers-in-sandboxes.md`.
- **Editable command prompt.** `claude-wrapper.sh` presents the launch
  command via `read -e -i` (readline-editable with seeded default).
  Replaces the old 3-option abort/new/continue menu. Default reflects
  state: `dtach -a /sandbox/.dtach-claude` if session exists, else
  `dtach -c /sandbox/.dtach-claude claude --dangerously-skip-permissions [-c]`.
  User can edit to any command (e.g., remove `--dangerously-skip-permissions`).
  Empty = bash shell. Ctrl+C = abort.
- **`validate-profile.sh` runs every connect.** `claude-wrapper.sh` runs
  `validate-profile.sh` before showing the command prompt — on every
  connect, not just first launch. No ACK gate; validation output is
  informational. Validates auth, credentials, OTEL, network
  reachability, and git auth symmetrically — each profile checks both
  presence of its own config and absence of the other's.
- **`--dryrun` flag.** `run()` wrapper prints commands instead of executing.
  `exec` calls exit cleanly in dryrun. Dryrun propagates through `--ensure`
  and `--recreate` sub-invocations via `--dryrun` arg forwarding. `.env`
  content printed with tokens redacted.
- **`--recreate` (image upgrade workflow).** Downloads repos + claude session
  state, deletes remote sandbox only (preserves local dir), creates fresh
  sandbox with `--no-clone --no-connect`, uploads local repos, connects. Used
  when sandbox image changes.
- **OAuth credential preservation across `--recreate`.** `download_claude_state()`
  downloads `/sandbox/.claude/.credentials.json` and `/sandbox/.claude.json`
  before deletion. `upload_claude_state()` restores both after creating the
  fresh sandbox. `.credentials.json` goes into the staged `.claude/` directory.
  `.claude.json` also goes into `.claude/` then gets `exec mv`'d to
  `/sandbox/.claude.json` (workaround: cannot upload single file to `/sandbox`
  due to gotcha #12, and cannot upload to `/` due to permission denied).
  See [knowledgebase: oauth-tokens](https://github.com/jewzaam/knowledgebase/blob/main/claude-code/oauth-tokens.md)
  for why both files are required.
- **`--no-connect` flag.** Creates sandbox without auto-starting Claude. Used
  by `--recreate` to allow upload step before connecting.
- **`connect_sandbox()` function.** Extracted exec connection command (keepalive
  + bashrc + claude-wrapper) into reusable function. All connect/ensure/create
  paths call it.
- **Hash-based sandbox naming.** OpenShell has a 19-char name limit (DNS label
  constraint: 19+2+19+2+19=61 < 63). `short_name()` generates `sb-<12-char-md5>`
  from the full name. `resolve_openshell_name()` reads `openshell_name` from
  manifest, falls back to `short_name()`. `resolve_full_name()` scans all
  manifests to reverse-map. `--list` annotates openshell names with full names.
- **Claude session state preservation.** `~/sandboxes/<name>/claude/projects/`
  stores session transcripts and project memory downloaded from sandbox.
  `download_claude_state()` pulls `/sandbox/.claude/projects/`.
  `upload_claude_state()` restores it at create time. Called during
  `--download` and uploaded during `--create`. `--refresh` and `--delete` do
  not touch it.
- **gws CLI integration.** `@googleworkspace/cli` installed via npm in
  Containerfile. Sandbox gets readonly OAuth credentials from
  `~/.config/gws-sandbox/`. `ensure_gws_creds()` validates token via
  `gws auth status` (`token_valid` field), re-auths with `--scopes` if expired
  or missing. Scopes defined in `GWS_SANDBOX_SCOPES` (all readonly). Client
  secret copied from `~/.config/gws/client_secret.json` on first auth.
- **Git commit signing.** `upload_config()` uploads the SSH signing key
  referenced by `git config --global user.signingkey` and a path-rewritten
  `.gitconfig` (`${HOME}` → `/sandbox`). Dedicated signing-only key, not the
  GitHub SSH auth key.
- **Custom sandbox image.** `--from openshell-sandbox:latest` in create
  command. Image must be built with `make build` before creating sandboxes.
  Previously was using the default NVIDIA base image without the custom tooling.
- **PR context generation.** `scripts/generate-pr-context.sh` generates
  `pr-context.md` in repo dirs for repos with `ref=pr/<num>` and GitHub URLs.
  Accepts optional second argument for profile name. When profile is `personal`,
  skips entire Jira section (no header, no key extraction, no auth attempt); PR
  metadata from `gh` still generated. `generate_pr_context()` wrapper in
  `sandbox.sh` passes `${SANDBOX_PROFILE:-}`. Fetches PR metadata via `gh pr
  view` (title, body, branch, base, labels, assignees — no review comments to
  avoid biasing agent reviews). Extracts `ANSTRAT-\d+` and `AAP-\d+` from
  title/branch/body, fetches linked Jira issues (summary, description, AC).
  Called during `--refresh` (generates + uploads pr-context.md per repo) and
  `--create` (generates between clone and upload loops).
- **`scode` existing sandbox dir mode.** `scode ~/sandboxes/<name>` detects
  `manifest.json`, reads repo URLs, builds `--ensure` command with all repos.
  Supports re-creating sandboxes from pre-existing local state without manually
  specifying repos.
- **`scode` PR URL mode.** `scode https://github.com/org/repo/pull/123` parses
  the GitHub PR URL via regex, extracts org/repo and PR number, constructs SSH
  clone URL (`git@github.com:org/repo.git`), sets ref to `pr/<num>`, names
  sandbox `<repo>-pr-<num>`, and runs `--ensure` with those args. No
  `--source-dir` since there is no local checkout.
- **Debian apt network access.** `policies/code.yaml` includes `deb.debian.org`
  on ports 80 and 443. Sandbox can install system packages at runtime.

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
15. `host: "**"` rejected by L7 validation — "host wildcard matches all hosts; use specific patterns like `*.example.com`". No match-all host wildcard supported.
16. TLD wildcards (`*.com`, `*.org`) rejected — "TLD wildcard not allowed; use subdomain wildcards like `*.example.com` instead".
17. `openshell policy set` returns exit 0 even when L7 validation fails. Policy application is async. Check `openshell policy list <name>` for `Failed`/`Loaded`/`Effective` status. `sandbox.sh --policy` handles this automatically.
18. OpenShell injects `ALL_PROXY=http://10.200.0.1:3128` and lowercase `http_proxy`/`https_proxy`/`no_proxy` into sandbox processes. `ALL_PROXY` overrides user-set `HTTPS_PROXY`. Must unset `ALL_PROXY` and set lowercase variants to override.
19. `host.containers.internal` resolves to `169.254.1.2` but is NOT directly reachable from sandbox. All traffic forced through L7 proxy at `10.200.0.1:3128`. Cannot bypass the proxy for direct host access.
20. `sandbox exec` connections drop during idle. No gRPC keepalive configuration exposed. Workaround: background ENQ keepalive in the exec bash command.
21. `openshell sandbox exec` requires `--name` flag. The sandbox name is not positional for exec. Pattern: `openshell sandbox exec --name "$name" "${GW_FLAG[@]}" -- command`.

## Reboot Recovery

After system reboot, two things break:

1. **Rootless-netns is stale.** Pasta's rootless network namespace references
   interfaces from the previous boot. Run `scripts/reset-rootless-netns.sh`
   before starting the gateway. This stops all containers, kills pasta,
   removes the netns dir, restarts podman socket, then restarts the containers.

2. **Sandbox JWTs may be expired.** Gateway now mints tokens with `exp=0` (no
   expiry) for local single-player mode. New sandboxes do not need post-reboot
   token refresh. For pre-existing sandboxes with expired tokens:
   `scripts/mint-sandbox-token.py` mints `exp=0` tokens, finds containers by
   `openshell.ai/sandbox-name` label (not hardcoded container name), delivers
   token via `podman cp` into stopped container overlay, then starts it.
   `scripts/mint-sandbox-tokens.sh` iterates all errored sandboxes from
   `openshell sandbox list`.

## Shell Script Gotchas

- **`.env` newline loss.** Bash `$()` command substitution strips trailing
  newlines. When building `.env` content with `printf '%s=%q\n'` inside `$()`,
  the final newline is lost. Append `$'\n'` explicitly outside the substitution.

## Development Workflow

1. Edit files
2. `make build` if Containerfile, bin/, or config/ changed
3. Test with `scripts/sandbox.sh --create test`
4. No rebuild needed for policy-only or env var changes
5. Use `scripts/sandbox.sh --refresh` to push config changes without rebuilding

## Standards

- Shell scripts: `set -euo pipefail`, no semicolons for chaining (use `&&`)
- Makefile: follows `~/source/standards/build/makefile.md` (verb-noun targets, self-documenting help)
- Naming: `~/source/standards/common/naming.md` (lowercase, hyphens)
- Local config: `~/source/standards/common/local-config-split.md` (`local.yaml` gitignored)
- Container tool: podman (not docker). `CONTAINER_TOOL ?= podman` in Makefile
- License: Apache 2.0
