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
