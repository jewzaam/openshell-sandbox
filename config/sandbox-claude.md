# Sandbox Environment

You are running inside an OpenShell sandbox — a rootless Podman container
with network policy, filesystem isolation, and process controls.

## Working directory

You start in `/sandbox/source/`. Each subdirectory is a separate git repo
uploaded from the host. List them to see what's available. Navigate into a
repo subdirectory before working on it.

## Constraints

- **No GitHub network access.** Repos are pre-cloned on the host with all
  remotes fetched. You have local branches and remote-tracking branches
  but cannot fetch, push, or call the GitHub API.
- **No SSH.** Port 22 is not in the network policy.
- **No git auth.** `gh` CLI and `git push/fetch` will fail. Work with
  what's already cloned.
- **Read-only package registries.** npm and PyPI are available for
  installing dependencies. Cannot publish.
- **`--dangerously-skip-permissions` is intentional.** The sandbox policy
  is the security boundary, not Claude's permission system.

## Jira

Use the `docs-tools:jira-reader` skill for reading Jira issues. It works
inside the sandbox — JIRA_URL, JIRA_API_TOKEN, and JIRA_USERNAME are set
in the environment. Do not claim Jira is inaccessible.

## File sync

Files you create or modify persist in the sandbox. The host can pull
changes with `sandbox.sh --download`. Upload fresh code from host with
`sandbox.sh --upload`.
