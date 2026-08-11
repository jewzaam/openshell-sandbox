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
- **Read-only package registries.** npm, PyPI, and Debian apt are available
  for installing dependencies. Cannot publish. Use `sudo apt-get install`
  for system packages.
- **`--dangerously-skip-permissions` is intentional.** The sandbox policy
  is the security boundary, not Claude's permission system.

## Jira

Use the `docs-tools:jira-reader` skill for reading Jira issues. It works
inside the sandbox — JIRA_URL, JIRA_API_TOKEN, and JIRA_USERNAME are set
in the environment. Do not claim Jira is inaccessible.

## Observability

Prometheus, Loki, and an OTEL collector run on the host and are reachable
from the sandbox:

- **Prometheus:** `http://172.30.0.11:9090` — PromQL queries via `/api/v1/query`
- **Loki:** `http://172.30.0.12:3100` — LogQL queries via `/loki/api/v1/query_range`
- **OTEL collector:** `http://172.30.0.10:4318` — receives telemetry from this sandbox

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
and acceptance criteria for referenced ANSTRAT or AAP tickets. For PR-based
repos, Jira keys are extracted from the PR title, branch, and body.
For Jira-seeded sandboxes (no repos), the file is at `/sandbox/source/jira-context.md`.
Read this file for requirements context.

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
