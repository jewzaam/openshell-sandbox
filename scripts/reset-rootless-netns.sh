#!/usr/bin/env bash
#
# Reset the rootless podman network namespace.
# Use when switching network interfaces (wired↔wifi) or after a pasta
# version change. Stops all containers, kills pasta, recreates the
# rootless-netns, then restarts the containers that were running.

set -euo pipefail

UID_NUM="$(id -u)"
NETNS_DIR="/run/user/${UID_NUM}/containers/networks/rootless-netns"
PID_FILE="${NETNS_DIR}/rootless-netns-conn.pid"

echo "=== Capturing running containers ==="
RUNNING=$(podman ps -q)
if [ -n "${RUNNING}" ]; then
  echo "Running containers:"
  podman ps --format '{{.Names}}' | while read -r name; do echo "  ${name}"; done
else
  echo "  (none)"
fi

echo "=== Stopping all containers ==="
podman stop -a -t 10 2>/dev/null || true

echo "=== Killing pasta process ==="
if [ -f "${PID_FILE}" ]; then
  PASTA_PID="$(cat "${PID_FILE}")"
  kill "${PASTA_PID}" 2>/dev/null || true
  echo "  killed PID ${PASTA_PID}"
else
  echo "  no PID file found"
fi

echo "=== Removing rootless-netns ==="
rm -rf "${NETNS_DIR}"
echo "  removed ${NETNS_DIR}"

echo "=== Restarting podman socket ==="
systemctl --user restart podman.socket

echo "=== Restarting containers ==="
if [ -n "${RUNNING}" ]; then
  for id in ${RUNNING}; do
    name=$(podman inspect --format '{{.Name}}' "${id}" 2>/dev/null || echo "${id}")
    if podman start "${id}" 2>/dev/null; then
      echo "  started ${name}"
    else
      echo "  FAILED to start ${name} — may need podman-compose up"
    fi
  done
else
  echo "  (no containers to restart)"
fi

echo "=== Done ==="
