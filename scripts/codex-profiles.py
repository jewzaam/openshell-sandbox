#!/usr/bin/env python3
"""Stage only the Codex profiles explicitly authorized for one sandbox profile."""

import json
import pathlib
import re
import shlex
import sys
import tomllib
import urllib.parse


PROFILE_KEYS = {
    "model", "model_provider", "model_catalog_json", "model_reasoning_effort",
    "model_context_window", "model_auto_compact_token_limit",
    "model_auto_compact_token_limit_scope", "model_reasoning_summary", "model_verbosity",
}


def toml_value(value):
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{json.dumps(k)} = {toml_value(v)}" for k, v in value.items()) + " }"
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(v) for v in value) + "]"
    if not isinstance(value, (str, bool, int, float)):
        raise ValueError("unsupported value in Codex profile configuration")
    return json.dumps(value, ensure_ascii=False)


def toml_table(path, values):
    header = ".".join(json.dumps(part) for part in path)
    return f"[{header}]\n" + "".join(f"{json.dumps(k)} = {toml_value(v)}\n" for k, v in values.items())


def stage(root, destination, sandbox_profile, names):
    names = sorted(set(names.split()))
    if any(not re.fullmatch(r"[A-Za-z0-9_-]+", name) for name in names):
        raise ValueError("Codex profile names must contain only letters, digits, underscores, and hyphens")
    host = {}
    if names:
        with (root / "config.toml").open("rb") as stream:
            host = tomllib.load(stream)
    providers, profiles, files = {}, {}, {}
    keys, urls, endpoints = set(), set(), set()
    for name in names:
        with (root / f"{name}.config.toml").open("rb") as stream:
            source = tomllib.load(stream)
        profile = {k: v for k, v in source.items() if k in PROFILE_KEYS}
        provider = profile.get("model_provider", "openai")
        table = host.get("model_providers", {}).get(provider)
        if table is None:
            if provider != "openai" or sandbox_profile != "work":
                raise ValueError("bound profile needs an explicit model provider for this sandbox profile")
        else:
            if table.get("requires_openai_auth") and sandbox_profile != "work":
                raise ValueError("OpenAI authentication is only published into work sandboxes")
            url = table.get("base_url", "")
            parts = urllib.parse.urlsplit(url)
            if (parts.scheme not in {"https", "http"} or not parts.hostname
                    or parts.username or parts.password or parts.query or parts.fragment
                    or any(char.isspace() for char in url)):
                raise ValueError("bound provider needs an HTTP(S) base_url without credentials, query, or fragment")
            port = parts.port
            if port is None:
                port = 443 if parts.scheme == "https" else 80
            if not 1 <= port <= 65535:
                raise ValueError("invalid provider port")
            urls.add(url)
            endpoints.add((parts.hostname, port))
            for key in [table.get("env_key"), *table.get("env_http_headers", {}).values()]:
                if key is not None:
                    if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                        raise ValueError("invalid provider credential environment variable name")
                    keys.add(key)
            providers[provider] = table
        if "model_catalog_json" in profile:
            catalog = pathlib.Path(profile["model_catalog_json"]).expanduser()
            if not catalog.is_absolute():
                catalog = root / catalog
            # Parse before staging so a missing or invalid catalog cannot silently fall back.
            contents = json.loads(catalog.read_text())
            files[f"{name}.models.json"] = json.dumps(contents) + "\n"
            profile["model_catalog_json"] = f"/sandbox/.codex/{name}.models.json"
        files[f"{name}.config.toml"] = "".join(f"{json.dumps(k)} = {toml_value(v)}\n" for k, v in profile.items())
        profiles[name] = profile

    # Match the host layout: provider tables belong in config.toml, profile
    # settings stay in <name>.config.toml. A [profiles.<name>] table here would
    # shadow the profile file and break `codex --profile <name>`.
    fragment = "".join(toml_table(("model_providers", name), table) for name, table in providers.items())
    tomllib.loads(fragment)
    policy = ""
    if endpoints:
        policy = "  codex_provider:\n    name: codex-provider\n    endpoints:\n"
        for host, port in sorted(endpoints):
            policy += f"      - host: {json.dumps(host)}\n        port: {port}\n"
            policy += "        protocol: rest\n        enforcement: enforce\n        access: full\n"
        policy += '    binaries:\n      - { path: "/**" }\n'
    receipt = {
        "sandbox_profile": sandbox_profile,
        "profiles": {name: profile.get("model_provider", "openai") for name, profile in profiles.items()},
        "keys": sorted(keys), "urls": sorted(urls),
    }
    destination.mkdir(parents=True, exist_ok=True)
    for filename, contents in files.items():
        (destination / filename).write_text(contents)
    (destination / "providers.toml").write_text(fragment)
    (destination / "policy.yaml").write_text(policy)
    (destination / "bindings.json").write_text(json.dumps(receipt, sort_keys=True) + "\n")
    print("CODEX_VARS=(" + " ".join(shlex.quote(key) for key in sorted(keys)) + ")")
    print("CODEX_PROVIDER_URLS=" + shlex.quote(" ".join(sorted(urls))))


if __name__ == "__main__":
    try:
        stage(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4])
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        # Do not echo configuration values or parser excerpts into logs.
        print(f"Error: cannot stage bound Codex profiles ({type(error).__name__})", file=sys.stderr)
        sys.exit(1)
