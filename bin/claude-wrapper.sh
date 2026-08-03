#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/claude.env"

# Validate profile before launching Claude
"${SCRIPT_DIR}/validate-profile.sh"

echo ""
echo "  1) Continue previous session (-c)"
echo "  2) Start new session"
echo "  3) Abort"
echo ""
read -rp "Select [1/2/3] (default: 1): " choice

case "${choice:-1}" in
    1) exec claude --dangerously-skip-permissions -c ;;
    2) exec claude --dangerously-skip-permissions ;;
    *) echo "aborted." && exit 1 ;;
esac
