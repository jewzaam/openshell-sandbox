#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Re-source runtime env: the wrapper may run from a shell whose .env snapshot
# predates a `sandbox.sh --refresh` (bashrc sourced it at shell start), and the
# agent process freezes its env at launch — stale values here mean every
# session and sub-agent reports against the old collector until relaunch. Also
# supplies $SANDBOX_PROFILE for the branching below.
#
# Telemetry behaviour is not sourced here. It lives in config/bashrc so every
# process in the container inherits it, not just the ones this wrapper starts.
if [[ -f /sandbox/.env ]]; then
    set -a
    source /sandbox/.env
    set +a
fi

# Always validate profile
"${SCRIPT_DIR}/validate-profile.sh"

# Seconds to answer the harness prompt before the default is taken. Short
# enough that `--connect` in a script or a muscle-memory Enter is not a stall,
# long enough to read the line. `read -t` returns non-zero and leaves the
# variable EMPTY on timeout — the `-i` prefill is not kept — so every read of
# it below falls back explicitly. Same path covers a non-tty stdin, which
# returns immediately on EOF.
HARNESS_PROMPT_TIMEOUT="${HARNESS_PROMPT_TIMEOUT:-5}"

socket_for() { echo "/sandbox/.dtach-$1"; }

# The remembered harness, passed in by connect_sandbox() out of the host's
# manifest.json — the only store. It lives on the host, so it survives
# --recreate (which deletes the remote sandbox, never ~/sandboxes/<name>) and
# host tooling reads it without coming in here. A sandbox cannot write the
# manifest back — gotcha 6 — so a pick made at the prompt below applies to this
# launch only; `--harness` changes the memory.
HARNESS_DEFAULT="${HARNESS_DEFAULT:-}"
valid_harness() { [[ "$1" == claude || "$1" == codex ]]; }
valid_harness "$HARNESS_DEFAULT" || HARNESS_DEFAULT=""

# Used when the manifest has no harness recorded yet.
HARNESS_FALLBACK=claude

# What to offer when nothing was named on the command line. In precedence:
#
# 1. A live dtach socket. Reattaching to the session already running is the
#    intent nearly every time, and it is the only signal here that reflects
#    what this sandbox is doing right now. Two live sockets is not a signal —
#    both agents are up and neither is the better guess — so it falls through.
# 2. Whatever was launched here last.
# 3. HARNESS_FALLBACK.
#
# Deliberately NOT profile-based. The profile says which credentials and which
# network policy a sandbox got, not which agent the human wants this time: the
# work profile carries both Anthropic and OpenAI egress and runs either.
#
# Emits "<harness> <reason>" from ONE set of branches. Recomputing the reason
# separately drifts from the chooser — it reports a value the chooser rejected.
default_harness() {
    local live=() h
    for h in claude codex; do
        [[ -S "$(socket_for "$h")" ]] && live+=("$h")
    done
    if [[ ${#live[@]} -eq 1 ]]; then
        echo "${live[0]} session running"
    elif [[ -n "$HARNESS_DEFAULT" ]]; then
        echo "$HARNESS_DEFAULT remembered"
    else
        echo "$HARNESS_FALLBACK default"
    fi
}

# $1 comes from `sandbox.sh --connect NAME <harness>`. Naming one is a decision
# already made, so it skips the prompt outright.
HARNESS="${1:-}"
if [[ -z "$HARNESS" ]]; then
    read -r default default_reason < <(default_harness)
    answer=""
    read -t "$HARNESS_PROMPT_TIMEOUT" -erp \
        "Harness [${default} - ${default_reason}] ${HARNESS_PROMPT_TIMEOUT}s: " \
        -i "$default" answer || true
    HARNESS="${answer:-$default}"
    echo ""
fi
case "$HARNESS" in
    claude|codex) ;;
    *) echo "Unknown harness '${HARNESS}' (expected claude or codex)" >&2; exit 1 ;;
esac

# One socket per harness, so Claude and Codex can both be live in the same
# sandbox and each --connect reattaches to its own. Claude keeps the original
# path: a session running when this landed stays reachable.
SOCKET="$(socket_for "$HARNESS")"

# The system prompt upload_static() ships lands at /sandbox/source/CLAUDE.md,
# which Codex does not read. $CODEX_HOME/AGENTS.md is loaded unconditionally,
# whatever the cwd, so one symlink is the whole mechanism — nothing to add to
# the upload, and no second copy to drift. Relinked on every launch because the
# target is rewritten by every `sandbox.sh --refresh`. Keyed on the harness, not
# the profile: any profile can run Codex now.
if [[ "$HARNESS" == "codex" && -f /sandbox/source/CLAUDE.md ]]; then
    mkdir -p /sandbox/.codex
    ln -sfn /sandbox/source/CLAUDE.md /sandbox/.codex/AGENTS.md
fi

# Default command reflects current state
if [[ -S "$SOCKET" ]]; then
    cmd="dtach -a $SOCKET"
elif [[ "$HARNESS" == "codex" ]]; then
    # Same bargain as --dangerously-skip-permissions below, for the same
    # reason: the OpenShell policy is the security boundary, so Codex's own
    # sandbox, approval prompts and hook-trust gate are redundant confinement
    # inside it. Every hook in here was uploaded from the host by
    # upload_config(), so there is no untrusted hook for the gate to catch — it
    # only costs a prompt on the observe-hook that reports state to
    # claude-dashboard. No --model: unlike the Anthropic profiles there is
    # nothing to correct for.
    #
    # `resume` unconditionally, with no check for existing sessions. Its picker
    # opens a new session as easily as it resumes one and works fine when there
    # are none, so branching on `-d /sandbox/.codex/sessions` bought nothing.
    # There is no --yolo in codex 0.152.0; the long flags are the flags.
    cmd="dtach -c $SOCKET codex resume --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust"
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

echo "Edit command below (empty = bash shell, Ctrl+C = abort):"
read -erp "> " -i "$cmd" user_cmd

if [[ -z "$user_cmd" ]]; then
    exec bash
fi

exec $user_cmd
