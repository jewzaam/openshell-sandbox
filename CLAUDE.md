# Claude Agent Instructions

OpenShell sandbox configuration for running Claude Code in auto mode inside
rootless Podman containers. Shell scripts, YAML policies, and a Containerfile —
not a Python project. Profiles: `code` (default, work), `personal`, `research`,
and `fetch-service` (applied temporarily by `sandbox.sh --fetch-service`).

> This file loads into every session in this repo. It holds only what costs real
> time to rediscover — external tool behavior, and places where the obvious
> change is silently wrong. Anything derivable from reading the code belongs in
> a comment at the code, not here.

## Not obvious from the file tree

- `config/site.env` — gitignored, per-machine (this repo is public; no tailnet
  hostnames in git). Deliberately **not** auto-created from
  `config/site.env.example`: silently adopting the template's collector address
  would point a sandbox at a host that may not exist here. Do not add a `cp`
  fallback. Supplies `OTEL_URL`, `PROMETHEUS_URL`, `LOKI_URL` (all required)
  and optional `DEFAULT_PROFILE`.
- `policies/local.yaml` — gitignored, for local overrides.
- `docs/configuration-model.md` — a **draft** proposal, not implemented. Do not
  read it as current behavior.
- `tests/test-*.sh` — runnable self-checks, no framework. `make test-unit` runs
  them all; run one directly when iterating. They live outside `scripts/`
  because that directory is on `$PATH`. Each synthesises its own
  `config/site.env` when none exists, so they pass on a fresh clone and in CI.

## Rules where the obvious change is wrong

1. **The sandbox is the security boundary.**
   `--dangerously-skip-permissions` is intentional. Network policy (L4/L7),
   Landlock filesystem, and process isolation replace Claude's permission
   system. Do not "fix" the flag.
2. **Never hand `policies/*.yaml` to `openshell` directly.** They are templates.
   An unsubstituted `${OTEL_HOST}` is valid YAML, and OpenShell accepts it as a
   literal hostname — the sandbox then silently denies all traffic.
   `render_policy()` substitutes from `site.env` and fails on any leftover
   placeholder.
3. **`render_policy()` renders to a temp file; only `install_policy()` writes
   `~/sandboxes/<name>/openshell-policy.yaml`, and only after the enforcer has
   accepted the policy.** That file *is* the record of what is in force, so a
   path that does not apply a policy cannot change it. Rendering straight into
   the sandbox dir looks harmless and makes the artifact lie — `--refresh` used
   to render the profile default over an applied `fetch-service` policy and
   upload it, dropping blocks the enforcer still allowed. `sandbox-claude.md`
   tells sessions to trust that file. `tests/test-policy-artifact.sh` fails
   if rendering ever writes into the sandbox dir again.
4. **Endpoint host/port derive from the `site.env` URLs** via `urllib.parse`.
   Do not add `*_HOST`/`*_PORT` keys — the same value in two places, free to
   drift, with nothing checking it.
5. **`--profile` applies at build time only** and the script rejects it
   elsewhere. It decides four things at once (`.env` contents, credential
   uploads, rendered policy, whether the system prompt keeps its Jira section)
   and only the create path writes all four; half-applied reads as applied.
   `--recreate NAME --profile <name>` is the only complete way to switch an
   existing sandbox.
6. **Host-owned files upload, never download.** `download_sandbox()` pulls only
   the repo directories named in the manifest, so a session cannot widen its own
   policy or rewrite its repo list by editing its copy.
7. **The dummy OTEL hooks (`python3 -c ""`) must survive settings.json
   stripping.** Claude Code emits no OTEL events for a hook type with no
   registered hook; those entries exist solely to trigger telemetry.
8. **`useradd -d /sandbox` in the Containerfile.** The default `/home/sandbox`
   breaks gitconfig and env sourcing across `sandbox exec` calls.
9. **`host.containers.internal` is unpoliced on every port.** OpenShell cannot
   selectively block ports on the container gateway host, regardless of policy.
   Keep anything that needs port-level policy on its own address, as the
   observability stack is on `172.30.0.10-12`.
10. **Personal profile telemetry is push-only by design.** Collector allowed,
    Prometheus and Loki blocked, so a personal sandbox cannot read work session
    data back. It looks like a missing rule; it is not.
    `validate-profile.sh` asserts the asymmetry.
11. **No repos are baked into the image.** `knowledgebase` and `standards` are
    cloned on the host and uploaded like any other repo.
12. **`.venv` is excluded in both directions** — host Python 3.14 vs sandbox
    3.13.
13. **`upload_repo()` pre-deletes the sandbox copy.** Without it, re-uploading a
    repo where a path flipped between symlink and directory fails with tar
    `Cannot open: File exists`.
14. **`manifest.json` is written before the sandbox is created, not after the
    repos are cloned.** `init_manifest()` (lib.sh) is called by scode before
    `code` opens the folder and by sandbox.sh before `openshell sandbox
    create`; the repo loop only fills in `.repos`. The file is an input, not
    bookkeeping — the host prompt reads `.profile` out of it, and moving the
    write back into the repo loop hides the profile behind create + clone +
    upload. `tests/test-manifest-timing.sh` fails if it slips.
15. **In `validate-profile.sh`, a missing URL is a FAIL, not a skip** — a
    skipped check reads identically to a passing one. `net_check` needs
    `--max-time`, not just `--connect-timeout`: the latter only bounds the hop
    to the L7 proxy, which always succeeds, so a stalled upstream hangs forever.

## Settled, do not re-evaluate

- **screen and tmux were tested and rejected** for session persistence — both
  mangle Claude Code's TUI through their terminal emulation layers. `dtach`
  only, socket at `/sandbox/.dtach-claude`, requires `/dev/pts` in policy
  `read_write`. See
  `knowledgebase/containers/terminal-multiplexers-in-sandboxes.md`.
- **`.claude.json` and `.credentials.json` are both required** to preserve
  OAuth across `--recreate`. See
  [knowledgebase: oauth-tokens](https://github.com/jewzaam/knowledgebase/blob/main/claude-code/oauth-tokens.md).
- **Sandbox names are hashed** because OpenShell enforces a 19-char limit (DNS
  label: 19+2+19+2+19=61 < 63). `short_name()` produces `sb-<12-char-md5>`.
- **`--ref pr/N` checks out through `gh pr checkout`**, so the branch is the
  PR's own head ref with a real upstream — a `git fetch pull/N/head:pr-N`
  branch has none, and reads as local-only to anything watching the checkout.
  The sandbox is still named `<repo>-pr-N`; only the branch changed. The
  refs/pull fetch remains as the no-gh/no-network fallback.
- **Context generation detects PRs from git, not manifest.** `generate_repo_context()`
  runs `gh pr view <arg>` on the host, where `<arg>` is the branch name, or the
  number when the branch is a fallback `pr-N` or its upstream is
  `refs/pull/N/head` (how `gh` records a fork PR — the head ref lives in the
  fork, so the name means nothing in the base repo). Manifest ref is updated to
  match, not the other way around. Switching branches locally and re-uploading
  regenerates context automatically.
- **Context files are separate.** `pr-context.md` (PR metadata only),
  `jira-context.md` (linked Jira issues), `open-prs.json` (all open PRs,
  structured). Never combined. `open-prs.json` is generated by
  `scripts/format-open-prs.py <org/repo>` — bot PRs are one-line entries,
  human PRs include files changed, base branch, merge state.
- **A gh failure is not evidence about the PR.** `gh pr view` exits 1 both for
  "no such PR" and for a 502, and the "no such PR" branch deletes
  `pr-context.md` and `jira-context.md`. `gh_pr_view_json()` returns 2 only
  when gh actually answered (`no pull requests found` / `Could not resolve`);
  anything else is 1 and the existing files are kept.
- **Only `gh pr checkout` retries** (`GH_RETRY_ATTEMPTS`, default 3, delay
  doubling from `GH_RETRY_DELAY`, default 2s). It decides what code is in the
  sandbox and runs once per repo at create time. Context generation runs on
  every upload for every repo, so a backoff there multiplies: with GitHub
  down, retrying `gh pr list` alone made a multi-repo upload take 3x as long
  for data that is optional. `tests/test-gh-retry.sh` asserts the one-call
  ceiling during an outage.
- **`open-prs.json` is always written for a GitHub repo, and is debounced.**
  No open PRs is `{"prs": []}`, not a missing file — absence used to mean
  "none", "gh failed", and "not GitHub" at once. `gh pr list --json files` is
  the slowest call in an upload and runs per repo, so a file younger than
  `OPEN_PRS_TTL_MINUTES` (default 60) is reused; set it to 0 to force. A failed
  fetch writes `fetch_error` + `fetch_error_at` into the file (keeping any real
  `prs` already there) so the failure is debounced like a success — these
  failures are repo-pinned, and a repo gh cannot read would otherwise burn a
  doomed call on every upload forever.
- **`scode` accepts Jira URLs.** `scode https://...atlassian.net/browse/KEY-123`
  fetches issue context into `jira-context.md`, creates a no-repo sandbox named
  `key-123` (lowercased).
- **`scode` accepts multiple PR URLs.** `scode PR_URL1 PR_URL2` for multi-repo
  review. Each becomes a `--repo`/`--ref` pair; sandbox named after first PR.
- **`ANTHROPIC_DEFAULT_{HAIKU,OPUS,SONNET}_MODEL` are stripped from the
  uploaded `settings.json` for every profile**, by
  `scripts/strip-settings.py`. A host pins models for host reasons; in a
  sandbox available models may differ.  Pinning model is not required.
- **Personal profile sets `--model claude-opus-5[1m]`** in the sandbox
  `claude-wrapper.sh`, off `$SANDBOX_PROFILE` from `/sandbox/.env`. Not off
  manifest.json — that is uploaded by `upload_static()` and used to lose the
  race on a first create, silently starting personal sessions on the default
  model.

## OpenShell Policy Gotchas

Hard-won, and referenced by number from `sandbox.sh` and
`docs/configuration-model.md` — do not renumber, simplify, or remove:

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
22. A policy endpoint needs both `protocol: rest` and `enforcement: enforce` for CONNECT to work. Omitting them (e.g. for intended L4-only passthrough) forwards an absolute-URI `GET` to that host:port but returns 403 on `CONNECT` to the same host:port. Match every working endpoint in `policies/` — both fields are always present together.

## Other gotchas

- **`yq` in the image is the kislyuk build (pip), not mikefarah/yq (Go).**
  Filters are jq syntax. The two share a name; the expression language differs.
- **Bash `$()` strips trailing newlines.** Building `.env` content with
  `printf '%s=%q\n'` inside `$()` loses the final newline — append `$'\n'`
  outside the substitution.
- **Debian apt is reachable but cannot install system-wide.** No `sudo`, `/usr`
  is read-only, `/var` is in neither filesystem list. Download-and-extract to
  `/tmp` works; the recipe is in `config/sandbox-claude.md`. The point is
  discovery — find a package, prove it, then add it to the Containerfile.

## Reboot Recovery

Two things break after a host reboot:

1. **Rootless-netns is stale.** Pasta's rootless network namespace references
   interfaces from the previous boot. Run `scripts/reset-rootless-netns.sh`
   before starting the gateway.
2. **Sandbox JWTs may be expired.** The gateway now mints `exp=0` tokens, so new
   sandboxes need nothing. For older ones, `scripts/mint-sandbox-tokens.sh`
   re-mints every errored sandbox.

## Development Workflow

1. Edit files
2. `make check` — shellcheck (warnings and up) + the `tests/` self-checks. Same
   two targets CI runs, so a green local run is a green PR.
3. `make build` if Containerfile, `bin/`, or `config/` changed
4. Test with `scripts/sandbox.sh --create test`
5. No rebuild needed for policy-only or env var changes
6. `scripts/sandbox.sh --refresh` pushes config changes without rebuilding

## Standards

- Shell scripts: `set -euo pipefail`, no semicolons for chaining (use `&&`)
- Makefile: follows `~/source/standards/build/makefile.md` — `check` is the
  default goal; `test-*` targets are the gate. The standard's Python targets
  (`test-format`, `test-typecheck`, `test-coverage`, `install-dev`) have no
  meaning in a shell repo and are deliberately absent.
- Workflows: `~/source/standards/build/github-workflows.md` — `test` runs
  `make test-unit`, `quality` runs `make test-lint`. Both call Make, never
  duplicate the commands.
- Naming: `~/source/standards/common/naming.md`
- Local config: `~/source/standards/common/local-config-split.md`
- Container tool: podman (not docker). `CONTAINER_TOOL ?= podman` in Makefile
- License: Apache 2.0
