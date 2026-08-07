#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/claude.env"

# Always validate profile
"${SCRIPT_DIR}/validate-profile.sh"

SESSION_NAME="claude"

# Default command reflects current state
if screen -list "$SESSION_NAME" 2>/dev/null | grep -q "\.${SESSION_NAME}[[:space:]]"; then
    cmd="screen -x $SESSION_NAME"
else
    cmd="screen -S $SESSION_NAME claude --dangerously-skip-permissions"
    if [[ -d /sandbox/.claude/projects ]]; then
        cmd="$cmd -c"
    fi
fi

echo ""
echo "Edit command below (empty = bash shell, Ctrl+C = abort):"
read -erp "> " -i "$cmd" user_cmd

if [[ -z "$user_cmd" ]]; then
    exec bash
fi

exec $user_cmd
