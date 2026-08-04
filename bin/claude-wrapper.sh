#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/claude.env"

# Validate profile before launching Claude
"${SCRIPT_DIR}/validate-profile.sh"

# Check for existing sessions
has_sessions=false
if [[ -d /sandbox/.claude/projects ]]; then
    has_sessions=true
fi

echo ""
echo "  1) Abort"
echo "  2) New session"
if [[ "$has_sessions" == true ]]; then
    echo "  3) Continue previous session (-c)"
    echo ""
    read -rp "Select [1/2/3] (default: 3): " choice
    default=3
else
    echo ""
    read -rp "Select [1/2] (default: 2): " choice
    default=2
fi

case "${choice:-$default}" in
    2) exec claude --dangerously-skip-permissions ;;
    3) exec claude --dangerously-skip-permissions -c ;;
    *) echo "aborted." && exit 1 ;;
esac
