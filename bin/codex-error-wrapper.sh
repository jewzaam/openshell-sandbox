#!/bin/bash

# Keep Codex's startup error outside dtach so it can be shown after dtach exits.
#
# The tee is a real background job on a fifo, not a `2> >(tee ...)` process
# substitution: a process substitution is not a job, so `wait` does not cover
# it and the log was read while tee still had the last lines in flight. That
# lost the "refresh token was revoked" message exactly when it mattered, and
# made tests/test-connect-harness.sh fail intermittently. Streaming is
# preserved — stderr still reaches the terminal line by line.
tmpdir="$(mktemp -d)"
log_pipe="${tmpdir}/stderr"
mkfifo "$log_pipe"
tee -a "$CODEX_ERROR_LOG" < "$log_pipe" >&2 &
tee_pid=$!

"$@" 2>"$log_pipe"
status=$?

wait "$tee_pid" || true
rm -rf "$tmpdir"
exit "$status"
