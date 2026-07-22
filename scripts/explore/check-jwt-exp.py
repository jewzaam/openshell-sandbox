#!/usr/bin/env python3
"""Check JWT expiration for a sandbox container. Usage: check-jwt-exp.py <container-id>"""
import json
import base64
import subprocess
import sys

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <container-id>", file=sys.stderr)
    sys.exit(1)

result = subprocess.run(
    ["podman", "exec", sys.argv[1], "cat", "/etc/openshell/auth/sandbox.jwt"],
    capture_output=True, text=True,
)
if result.returncode != 0:
    print(f"ERROR: {result.stderr.strip()}", file=sys.stderr)
    sys.exit(1)

token = result.stdout.strip()
parts = token.split(".")
payload = json.loads(base64.urlsafe_b64decode(parts[1] + "=="))
exp = payload.get("exp", "missing")
if exp == 0:
    print(f"exp: 0 (never expires)")
else:
    import time
    now = int(time.time())
    print(f"exp: {exp}")
    print(f"now: {now}")
    print(f"expired: {exp < now}")
    if exp > now:
        remaining = exp - now
        print(f"remaining: {remaining}s ({remaining // 3600}h {(remaining % 3600) // 60}m)")
