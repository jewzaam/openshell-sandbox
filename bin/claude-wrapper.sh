#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/claude.env"

# Validate profile before launching Claude
"${SCRIPT_DIR}/validate-profile.sh"

# Build default command: continue previous session if one exists
cmd="claude --dangerously-skip-permissions"
if [[ -d /sandbox/.claude/projects ]]; then
    cmd="$cmd -c"
fi

echo ""
echo "Edit command below (empty = bash shell, Ctrl+C = abort):"
read -erp "> " -i "$cmd" user_cmd

if [[ -z "$user_cmd" ]]; then
    exec bash
fi

exec $user_cmd
