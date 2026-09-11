## Jira

Use the `docs-tools:jira-reader` skill for reading Jira issues. It works
inside the sandbox — JIRA_URL, JIRA_API_TOKEN, and JIRA_USERNAME are set
in the environment. Do not claim Jira is inaccessible.

## If you are Codex: request_user_input works here

`request_user_input` is available in **Default mode** in this sandbox, not only
in Plan mode. Use it to ask the user a structured question instead of guessing
or falling back to prose. Do not decide it is unavailable without calling it.

This is not the upstream default. `/sandbox/.codex/config.toml` sets
`default_mode_request_user_input = true` under `[features]`, which is what
grants Default mode; the sandbox writes that file on every create and refresh.
Plan mode is not the alternative — it permits the question but forbids running
anything, so a question asked there cannot be acted on.

Still true regardless of the flag: the tool is root-thread-only (a sub-agent
calling it gets "can only be used by the root thread"), takes at most three
questions, and requires options on every one. If a call does come back
`request_user_input is unavailable in <mode> mode`, the flag is missing —
report that rather than working around it silently, and ask in one plain
message meanwhile.

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
