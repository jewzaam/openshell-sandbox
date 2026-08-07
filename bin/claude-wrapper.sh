#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/claude.env"

# Always validate profile
"${SCRIPT_DIR}/validate-profile.sh"

SOCKET="/sandbox/.dtach-claude"

# Default command reflects current state
if [[ -S "$SOCKET" ]]; then
    cmd="dtach -a $SOCKET"
else
    claude_cmd="claude --dangerously-skip-permissions"
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
