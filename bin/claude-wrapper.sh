#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Re-source runtime env before claude.env: the wrapper may run from a shell
# whose .env snapshot predates a `sandbox.sh --refresh` (bashrc sourced it at
# shell start). claude.env builds OTEL_RESOURCE_ATTRIBUTES from these values,
# and the claude process freezes its env at launch — stale values here mean
# every session and sub-agent reports without telemetry until relaunch.
if [[ -f /sandbox/.env ]]; then
    set -a
    source /sandbox/.env
    set +a
fi
source "${SCRIPT_DIR}/claude.env"

# Always validate profile
"${SCRIPT_DIR}/validate-profile.sh"

SOCKET="/sandbox/.dtach-claude"

# Default command reflects current state
if [[ -S "$SOCKET" ]]; then
    cmd="dtach -a $SOCKET"
else
    claude_cmd="claude"
    # $SANDBOX_PROFILE comes from /sandbox/.env, written and uploaded on the
    # create path itself. manifest.json was the old source and lost this race:
    # on a first create it reached the sandbox after the wrapper had already
    # started, so a personal sandbox silently came up on the default model.
    case "${SANDBOX_PROFILE:-}" in
        personal|home) claude_cmd="$claude_cmd --model claude-opus-5[1m]" ;;
    esac
    claude_cmd="$claude_cmd --dangerously-skip-permissions"
    if [[ -d /sandbox/.claude/projects ]]; then
        claude_cmd="$claude_cmd -c"
    fi
    cmd="dtach -c $SOCKET $claude_cmd"
fi

echo ""
echo "Edit command below (empty = bash shell, Ctrl+C = abort):"
read -erp "> " -i "$cmd" user_cmd

if [[ -z "$user_cmd" ]]; then
    exec bash
fi

exec $user_cmd
