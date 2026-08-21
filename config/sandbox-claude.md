# Sandbox Environment

You are running inside an OpenShell sandbox — a rootless Podman container
with network policy, filesystem isolation, and process controls.

## Working directory

You start in `/sandbox/source/`. Each subdirectory is a separate git repo
uploaded from the host.

**On session start:**

1. Read `manifest.json` if present — it lists repos, the sandbox name
   (often indicates the primary repo), and which repo was added first
2. Read every repo's `CLAUDE.md` — each has build instructions, conventions,
   and context this file does not cover
3. If only one repo, `cd` into it automatically
4. If multiple repos, infer the target from the user's first message (the
   sandbox name and first repo in manifest are strong signals). Only ask if
   the message is truly ambiguous

## Constraints

- **No GitHub network access.** Repos are pre-cloned on the host with all
  remotes fetched. You have local branches and remote-tracking branches
  but cannot fetch, push, or call the GitHub API.
- **No SSH.** Port 22 is not in the network policy.
- **No git auth.** `gh` CLI and `git push/fetch` will fail. Work with
  what's already cloned.
- **Read-only package registries.** npm, PyPI, and Debian apt are reachable.
  Cannot publish. There is no `sudo`, and `/usr` and `/var` are read-only, so
  nothing installs system-wide. Project-local does work: `pip install --user`,
  `npm install` in a project directory. For a Debian package, point apt at a
  writable state directory and extract it yourself:

  ```bash
  mkdir -p /tmp/apt/lists/partial /tmp/apt/cache/archives/partial
  A="-o Dir::State=/tmp/apt -o Dir::State::Lists=/tmp/apt/lists
     -o Dir::Cache=/tmp/apt/cache -o Dir::State::status=/tmp/apt/status
     -o Debug::NoLocking=1"
  apt-get $A update && apt-cache $A search <name>
  cd /tmp/apt && apt-get $A download <name> && dpkg -x ./*.deb /tmp/apt/root
  # binary is at /tmp/apt/root/usr/bin/<name>
  ```

  If a package is worth having permanently, say so — it belongs in the
  image's Containerfile, not in a per-session workaround.
- **`--dangerously-skip-permissions` is intentional.** The sandbox policy
  is the security boundary, not Claude's permission system.

## Network policy

`/sandbox/source/openshell-policy.yaml` is the effective OpenShell policy for this
sandbox — which hosts and ports are reachable, and which filesystem paths are
writable.

- **Read-only.** It is uploaded from the host and never downloaded back.
  Editing it changes nothing; enforcement lives outside the sandbox.
- **Check it before concluding a host is unreachable**, and before working
  around a blocked request. A `403` from the egress proxy means the host is
  not in the policy — no retry, mirror, or alternate flag will change that.
- **It can change while this session runs.** If told the policy or network
  access changed, re-read the file rather than trusting an earlier read.
  Changes both add and remove hosts and can change ports.  All is mutable by 
  user from the host.

## Observability

Endpoints are site-specific: a container stack on the host machine for some
sandboxes, a k3s cluster over Tailscale for others. Never assume an address —
read one of these, both of which are current for this sandbox:

- `$OTEL_EXPORTER_OTLP_ENDPOINT` — where this session ships telemetry.
- `/sandbox/source/openshell-policy.yaml` — what is reachable at all. Under
  `network_policies:`, each block has a `name:` and `endpoints:` carrying
  `host:` and `port:`. The telemetry blocks are named `otel-collector`
  (push), `prometheus-read`, and `loki-read` (PromQL via `/api/v1/query`,
  LogQL via `/loki/api/v1/query_range`). A block that is absent means that
  service is not reachable from here — do not try it.

`yq` is installed. It is the kislyuk build, so filters are jq syntax:

```bash
# every reachable host:port, by policy name
yq -r '.network_policies[] | .name as $n | .endpoints[] | "\($n)\t\(.host):\(.port)"' \
    /sandbox/source/openshell-policy.yaml

# just the collector
yq -r '.network_policies.otel.endpoints[0] | "\(.host):\(.port)"' \
    /sandbox/source/openshell-policy.yaml
```

Claude Code emits OTEL metrics, logs, and traces. If the knowledgebase repo
is available at `/sandbox/source/knowledgebase/`, read
`claude-code/otel-native-telemetry.md` and `observability/` for event types,
label taxonomies, and query patterns.

## PR context

A repo may contain `pr-context.md` in its root. If present, it was generated
on the host from the GitHub PR. It contains PR metadata (title, branch,
labels, assignees) and the PR description. Read this file before reviewing
or working on the PR.

## Jira context

A repo or `/sandbox/source/` may contain `jira-context.md`. If present, it
was generated on the host from linked Jira issues — summary, description,
and acceptance criteria for referenced Jira tickets. For PR-based
repos, Jira keys are extracted from the PR title, branch, and body.
For Jira-seeded sandboxes (no repos), the file is at `/sandbox/source/jira-context.md`.
Read this file for requirements context.

## Open PRs

Every GitHub repo has an `open-prs.json` — structured data on all open pull
requests for that repository, generated on the host. `"prs": []` means the
repo has no open PRs, not that the data is missing. The file is refreshed at
most once an hour, so it can be up to that stale. A `fetch_error` key means
the host could not reach the GitHub API for that repo — `prs` is then stale or
absent, and its absence says nothing about whether PRs exist. Schema:

    {
      "prs": [{"number", "branch", "base", "title", "body", "merge_state",
               "files": [string], "labels"?: [string],
               "related_prs"?: [int], "jira_keys"?: [string]}],
      "bot_prs"?: [{"number", "title", "author"}],
      "cross_refs"?: [{"number", "related_prs"?, "jira_keys"?}],
      "fetch_error"?: string, "fetch_error_at"?: string
    }

`cross_refs` maps PRs that reference each other or share Jira keys — use
it to identify coordinated changes across PRs. `body` is the raw PR
description. `bot_prs` are dependency bumps. Use this to scope reviews:
verify "out of scope" claims, find merge-order dependencies, and spot
related work the PR author may not have linked.

## Completion gate

Before claiming work is complete on any repo that has a Makefile with a
`check` target: run the `/fix` skill. It runs `make check`, then
iteratively fixes failures (formatting, lint, type errors, test failures).
A commit cannot succeed if `make check` fails — do the work upfront, not
after the user asks why the commit was rejected.

## File sync

Files you create or modify persist in the sandbox. The host can pull
changes with `sandbox.sh --download`. Upload fresh code from host with
`sandbox.sh --upload`.
