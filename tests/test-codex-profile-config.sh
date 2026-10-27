#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TMP="$(mktemp -d)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/isolate.sh"
trap 'rm -rf "$TMP"' EXIT

HELPERS="${TMP}/helpers.sh"
sed -n '/^resolve_codex_profiles()/,/^}/p;/^stage_codex_profile_config()/,/^}/p;/^check_codex_profile_bindings()/,/^}/p;/^render_policy()/,/^}/p;/^codex_marketplace_data()/,/^}/p;/^render_codex_config()/,/^}/p' \
    "${REPO_ROOT}/scripts/sandbox.sh" > "$HELPERS"
sed -n '/^codex_profiles_bound()/,/^}/p' "${REPO_ROOT}/scripts/sandbox.sh" >> "$HELPERS"
# shellcheck disable=SC1090
source "$HELPERS"
SCRIPT_DIR="${REPO_ROOT}/scripts"

mkdir -p "${HOME}/.codex"
cat > "${HOME}/.codex/config.toml" <<'TOML'
[model_providers.team]
base_url = "https://work.example.invalid/v1"
env_key = "WORK_MODEL_KEY"
wire_api = "responses"
env_http_headers = { "X-Client" = "WORK_CLIENT_KEY" }
[model_providers.solo]
base_url = "https://personal.example.invalid:8443/v1"
env_key = "PERSONAL_MODEL_KEY"
[model_providers.unbound]
base_url = "https://DO-NOT-PUBLISH.example.invalid/v1"
env_key = "DO_NOT_PUBLISH_KEY"
experimental_bearer_token = "DO_NOT_PUBLISH_TOKEN"
[profiles.unbound]
model = "DO_NOT_PUBLISH_MODEL"
TOML

for name in team solo
 do
    cat > "${HOME}/.codex/${name}.config.toml" <<TOML
model = "${name}/model"
model_provider = "$name"
model_catalog_json = "${name}.models.json"
model_reasoning_effort = "high"
[projects."/home/private/work-project"]
trust_level = "trusted"
[model_providers.unbound]
base_url = "https://DO-NOT-PUBLISH.example.invalid"
TOML
    printf '{"models":[{"slug":"%s/model","instructions":"%s-only context"}]}\n' "$name" "$name" \
        > "${HOME}/.codex/${name}.models.json"
done
cp "${HOME}/.codex/team.config.toml" "${HOME}/.codex/shared.config.toml"
export CODEX_PROFILES_WORK='team shared'
export CODEX_PROFILES_PERSONAL=solo
export CODEX_PROFILES_HOME=solo
OTEL_URL=http://collector.example.invalid:4318
export OTEL_HOST=x OTEL_PORT=4318 PROMETHEUS_HOST=x PROMETHEUS_PORT=9090 LOKI_HOST=x LOKI_PORT=3100

for SANDBOX_PROFILE in work personal home
 do
    resolve_codex_profiles
    output="${TMP}/${SANDBOX_PROFILE}"
    stage_codex_profile_config "$output"
    render_codex_config "${HOME}/.codex/config.toml" "$OTEL_URL" > "${output}/.codex/config.toml"
    render_policy "${REPO_ROOT}/policies/${SANDBOX_PROFILE}.yaml" > "${output}/policy-path"
    python3 - "$output" "$SANDBOX_PROFILE" "$CODEX_PROFILE_STAGE" <<'PY'
import json
import pathlib
import sys
import tomllib

output, sandbox, stage = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3])
root = output / ".codex"
config = tomllib.loads((root / "config.toml").read_text())
expected = {"team", "shared"} if sandbox == "work" else {"solo"}
assert "profiles" not in config
assert set(config["model_providers"]) == ({"team"} if sandbox == "work" else {"solo"})
assert {p.name for p in root.glob("*.config.toml")} == {f"{name}.config.toml" for name in expected}
assert {p.name for p in root.glob("*.models.json")} == {f"{name}.models.json" for name in expected}
for name in expected:
    profile = tomllib.loads((root / f"{name}.config.toml").read_text())
    assert set(profile) <= {"model", "model_provider", "model_catalog_json", "model_reasoning_effort"}
    assert profile["model_catalog_json"] == f"/sandbox/.codex/{name}.models.json"
    assert json.loads((root / f"{name}.models.json").read_text())["models"]
text = "\n".join(path.read_text() for path in root.iterdir())
assert "DO_NOT_PUBLISH" not in text and "DO-NOT-PUBLISH" not in text
assert "/home/private" not in text
other = "solo" if sandbox == "work" else "team"
assert f"{other}-only context" not in text
policy = pathlib.Path((output / "policy-path").read_text().strip()).read_text()
assert ("work.example.invalid" in policy) == (sandbox == "work")
assert ("personal.example.invalid" in policy) == (sandbox != "work")
assert "DO-NOT-PUBLISH" not in policy
receipt = json.loads((stage / "bindings.json").read_text())
assert set(receipt["profiles"]) == expected
assert set(receipt["keys"]) == ({"WORK_MODEL_KEY", "WORK_CLIENT_KEY"} if sandbox == "work" else {"PERSONAL_MODEL_KEY"})
PY
    if [[ "$SANDBOX_PROFILE" == work ]]
    then
        [[ "${CODEX_VARS[*]}" == 'WORK_CLIENT_KEY WORK_MODEL_KEY' ]]
        [[ "$CODEX_PROVIDER_URLS" == 'https://work.example.invalid/v1' ]]
    else
        [[ "${CODEX_VARS[*]}" == PERSONAL_MODEL_KEY ]]
        [[ "$CODEX_PROVIDER_URLS" == 'https://personal.example.invalid:8443/v1' ]]
    fi
done

# Missing bindings grant nothing, even if the old selected-profile setting remains.
export CODEX_PROVIDER_PROFILE=team
CODEX_PROFILES_PERSONAL=''
SANDBOX_PROFILE=personal
resolve_codex_profiles
[[ ${#CODEX_VARS[@]} == 0 && -z "$CODEX_PROVIDER_URLS" ]]
! codex_profiles_bound && [[ ! -s "${CODEX_PROFILE_STAGE}/policy.yaml" ]]

# A merge upload must never leave revoked profile files or credentials behind.
mkdir -p "${TMP}/sandbox"
export CREATE_MODE=false
if check_codex_profile_bindings "${TMP}/sandbox" 2>/dev/null
then
    echo 'FAIL: legacy sandbox accepted without recorded bindings' >&2
    exit 1
fi
cp "${CODEX_PROFILE_STAGE}/bindings.json" "${TMP}/sandbox/codex-profile-bindings.json"
check_codex_profile_bindings "${TMP}/sandbox"
CODEX_PROFILES_PERSONAL=solo
resolve_codex_profiles
if check_codex_profile_bindings "${TMP}/sandbox" 2>/dev/null
then
    echo 'FAIL: changed bindings accepted without recreation' >&2
    exit 1
fi
CREATE_MODE=true check_codex_profile_bindings "${TMP}/sandbox"

# Invalid, absent, or malformed authorized artifacts fail rather than silently fallback.
for bad in missing '../team'
 do
    CODEX_PROFILES_PERSONAL="$bad"
    if resolve_codex_profiles 2>/dev/null
    then
        echo 'FAIL: invalid bound profile was accepted' >&2
        exit 1
    fi
done
CODEX_PROFILES_PERSONAL=solo
printf 'invalid JSON\n' > "${HOME}/.codex/solo.models.json"
if resolve_codex_profiles 2>/dev/null
then
    echo 'FAIL: malformed bound catalog was accepted' >&2
    exit 1
fi
[[ ${#CODEX_VARS[@]} == 0 && -z "$CODEX_PROVIDER_URLS" ]]
echo 'all codex-profile-config checks passed'
