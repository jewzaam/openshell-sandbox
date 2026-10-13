#!/bin/bash

# Keep Codex's startup error outside dtach so it can be shown after dtach exits.
"$@" 2> >(tee -a "$CODEX_ERROR_LOG" >&2)
status=$?
wait || true
exit "$status"
