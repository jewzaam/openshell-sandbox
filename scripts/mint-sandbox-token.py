#!/usr/bin/env python3
#
# Mint a fresh sandbox JWT for an existing sandbox.
# Writes to the bind-mounted token file so the supervisor picks it up on restart.
#
# Usage: python3 scripts/mint-sandbox-token.py <sandbox-name>
#
# Requires: PyJWT with Ed25519 support
#   pip install PyJWT[crypto]

import json
import os
import subprocess
import sys
import time

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <sandbox-name>", file=sys.stderr)
        sys.exit(1)

    sandbox_name = sys.argv[1]
    container_name = f"openshell-sandbox-{sandbox_name}"

    # Get sandbox ID from container label
    result = subprocess.run(
        ["podman", "inspect", "--format",
         '{{ index .Config.Labels "openshell.sandbox-id" }}',
         container_name],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"ERROR: container {container_name} not found", file=sys.stderr)
        sys.exit(1)
    sandbox_id = result.stdout.strip()

    # Find gateway JWT config from active gateway metadata
    config_home = os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))
    active_gw_path = os.path.join(config_home, "openshell", "active_gateway")
    if os.path.exists(active_gw_path):
        with open(active_gw_path) as f:
            active_gw = f.read().strip()
    else:
        active_gw = "podman-dev"

    # Try standard gateway state locations
    gateway_jwt_dir = None
    candidates = [
        os.path.expanduser(f"~/.local/state/openshell/gateway/tls/jwt"),
        os.path.join(os.environ.get("OPENSHELL_GATEWAY_STATE_DIR", ""), "tls", "jwt"),
    ]
    # Also check OpenShell dev cache (mise run gateway)
    for src_dir in [os.path.expanduser("~/source/OpenShell"), "."]:
        candidates.append(os.path.join(src_dir, ".cache", "gateway-podman", "tls", "jwt"))

    for candidate in candidates:
        if os.path.exists(os.path.join(candidate, "signing.pem")):
            gateway_jwt_dir = candidate
            break

    if not gateway_jwt_dir:
        print("ERROR: gateway JWT signing key not found. Searched:", file=sys.stderr)
        for c in candidates:
            print(f"  {c}", file=sys.stderr)
        sys.exit(1)

    signing_key_path = os.path.join(gateway_jwt_dir, "signing.pem")
    kid_path = os.path.join(gateway_jwt_dir, "kid")

    with open(signing_key_path, "rb") as f:
        signing_key = f.read()
    with open(kid_path) as f:
        kid = f.read().strip()

    # Mint token using openssl for signing (avoids Python cryptography version issues)
    now = int(time.time())
    import base64

    # Build JWT header and payload
    header = json.dumps({"alg": "EdDSA", "typ": "JWT", "kid": kid}, separators=(",", ":"))
    # Read gateway_id from active gateway metadata or gateway config
    gateway_id = active_gw
    gw_meta = os.path.join(config_home, "openshell", "gateways", active_gw, "metadata.json")
    if os.path.exists(gw_meta):
        with open(gw_meta) as f:
            meta = json.load(f)
            gateway_id = meta.get("name", active_gw)

    gateway_identity = f"openshell-gateway:{gateway_id}"
    payload = json.dumps({
        "sub": f"spiffe://openshell/sandbox/{sandbox_id}",
        "iss": gateway_identity,
        "aud": gateway_identity,
        "iat": now,
        "exp": now + 86400,
        "sandbox_id": sandbox_id,
    }, separators=(",", ":"))

    def b64url(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    signing_input = f"{b64url(header.encode())}.{b64url(payload.encode())}"

    # Sign with openssl (Ed25519 requires file input, not stdin pipe)
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as tmp_in, \
         tempfile.NamedTemporaryFile(suffix=".sig", delete=False) as tmp_out:
        tmp_in.write(signing_input.encode())
        tmp_in.flush()
        tmp_in_path = tmp_in.name
        tmp_out_path = tmp_out.name

    sig_result = subprocess.run(
        ["openssl", "pkeyutl", "-sign",
         "-inkey", signing_key_path,
         "-in", tmp_in_path,
         "-out", tmp_out_path,
         "-rawin"],
        capture_output=True,
    )
    os.unlink(tmp_in_path)
    if sig_result.returncode != 0:
        os.unlink(tmp_out_path)
        print(f"ERROR: openssl signing failed: {sig_result.stderr.decode()}", file=sys.stderr)
        sys.exit(1)

    with open(tmp_out_path, "rb") as f:
        signature = f.read()
    os.unlink(tmp_out_path)

    token = f"{signing_input}.{b64url(signature)}"

    # Write to token file
    state_dir = os.path.expanduser("~/.local/state/openshell")
    token_path = os.path.join(state_dir, "podman-sandbox-tokens", sandbox_id, "sandbox.jwt")

    os.makedirs(os.path.dirname(token_path), exist_ok=True)
    with open(token_path, "w") as f:
        f.write(token + "\n")
    os.chmod(token_path, 0o600)

    print(f"Token minted for sandbox {sandbox_name} (ID: {sandbox_id})")
    print(f"Written to: {token_path}")
    print(f"Expires: {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(now + 86400))}")
    print(f"\nRestart the container: podman stop {container_name} && podman start {container_name}")


if __name__ == "__main__":
    main()
