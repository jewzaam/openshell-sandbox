## This is a Codex sandbox

The agent here is Codex CLI, not Claude Code. `api.anthropic.com` is not in
this sandbox's network policy and will return 403 — that is the profile
working, not a misconfiguration. Do not try to reach it, and do not suggest
Claude Code as the fix for anything.

Reachable instead: `chatgpt.com` (the provider on a ChatGPT sign-in),
`api.openai.com` (the provider on an API key), and `auth.openai.com`
(`codex login` and every token refresh after it).

Credentials live at `/sandbox/.codex/auth.json`. Nothing uploads that file
from the host and nothing preserves it across `sandbox.sh --recreate`, so a
fresh sandbox is signed out.

Signing in needs no separate step: launching `codex` while signed out shows
the onboarding auth screen, and the option to take there is **"Sign in with
Device Code"**. The browser option binds `127.0.0.1:1455` and cannot complete
— there is no browser here. `codex login --device-auth` does the same thing
from a shell. There is no `/login` slash command; `/logout` exists and will
drop you back to that screen on the next launch.

The `## Reading telemetry back` section below is shared verbatim with the
`home` profile and describes Claude Code's exporter. Codex does not export
anything here: its telemetry is configured under `[otel]` in
`~/.codex/config.toml`, which this sandbox does not write. What you can read
back is whatever *other* sandboxes on this machine have pushed.

## Reading telemetry back

This sandbox may query its own telemetry. Endpoints are site-specific — a
container stack on the host machine for some sandboxes, a k3s cluster over
Tailscale for others — so never assume an address. Read them out of
`/sandbox/source/openshell-policy.yaml`. The blocks are `prometheus-read`
(PromQL via `/api/v1/query`) and `loki-read` (LogQL via
`/loki/api/v1/query_range`); `otel-collector` is the push endpoint and
answers no queries. A block that is absent means that service is not
reachable from here — do not try it.

```bash
yq -r '.network_policies[] | select(.name | test("prometheus|loki")) |
       "\(.name)\t\(.endpoints[0].host):\(.endpoints[0].port)"' \
    /sandbox/source/openshell-policy.yaml
```

Claude Code emits OTEL metrics, logs, and traces. If the knowledgebase repo
is available at `/sandbox/source/knowledgebase/`, read
`claude-code/otel-native-telemetry.md` and `observability/` for event types,
label taxonomies, and query patterns.
