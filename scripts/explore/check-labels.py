#!/usr/bin/env python3
"""Show openshell-related labels on all containers."""
import json
import subprocess

result = subprocess.run(
    ["podman", "ps", "-a", "--format", "json"],
    capture_output=True, text=True, check=True,
)
for c in json.loads(result.stdout):
    labels = c.get("Labels") or {}
    os_labels = {k: v for k, v in labels.items() if "openshell" in k.lower()}
    if os_labels:
        print(json.dumps({
            "Id": c["Id"][:12],
            "Names": c["Names"],
            "Labels": os_labels,
        }, indent=2))
