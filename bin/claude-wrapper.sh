#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/claude.env"

# Always validate profile
"${SCRIPT_DIR}/validate-profile.sh"

SOCKET="/sandbox/.dtach-claude"

# The system prompt upload_static() ships lands at /sandbox/source/CLAUDE.md,
# which Codex does not read. $CODEX_HOME/AGENTS.md is loaded unconditionally,
# whatever the cwd, so one symlink is the whole mechanism — nothing to add to
# the upload, and no second copy to drift. Relinked on every launch because the
# target is rewritten by every `sandbox.sh --refresh`.
if [[ "${SANDBOX_PROFILE:-}" == "codex" && -f /sandbox/source/CLAUDE.md ]]; then
    mkdir -p /sandbox/.codex
    ln -sfn /sandbox/source/CLAUDE.md /sandbox/.codex/AGENTS.md
fi

# Default command reflects current state
if [[ -S "$SOCKET" ]]; then
    cmd="dtach -a $SOCKET"
elif [[ "${SANDBOX_PROFILE:-}" == "codex" ]]; then
    # Same bargain as --dangerously-skip-permissions below, for the same
    # reason: the OpenShell policy is the security boundary, so Codex's own
    # sandbox and approval prompts are redundant confinement inside it. No
    # --model: unlike the Anthropic profiles there is nothing to correct for.
    codex_cmd="codex --dangerously-bypass-approvals-and-sandbox"
    if [[ -d /sandbox/.codex/sessions ]]; then
        codex_cmd="codex resume --last --dangerously-bypass-approvals-and-sandbox"
    fi
    cmd="dtach -c $SOCKET $codex_cmd"
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
