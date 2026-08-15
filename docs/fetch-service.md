# Fetch service

Reference for skills and sessions running **inside** a sandbox that need to
read public web pages.

## Why it exists

A sandbox cannot make HTTPS requests to arbitrary hosts. Its only egress is
OpenShell's HTTP CONNECT proxy, which permits only hosts named in the
sandbox's network policy. Research follows links discovered at runtime, so the
hosts are not knowable in advance and a per-host allowlist is not workable.

The fetch service runs on the **host**, outside the sandbox. The sandbox asks
it, over plain HTTP, to perform a request and return the result. The sandbox
never speaks TLS and never issues a CONNECT.

## Which tool to use

| Need | Use | Works in a sandbox |
|---|---|---|
| Find pages, search the web | `WebSearch` | **Yes** — runs server-side via `api.anthropic.com`, never egresses from the container |
| Read a specific URL | fetch service (below) | **Yes**, while the service is running |
| Read a specific URL | `WebFetch` | **No** — fails with `Socket is closed`; it egresses from the container and hits the proxy |

`WebSearch` is unaffected by any of this and needs no service running. Reach
for it first when the task is discovery rather than reading a known URL.

Do not attempt to work around `WebFetch` failing by calling `curl` directly on
the target URL — that fails the same way, for the same reason.

## Using it

```bash
FETCHSVC="http://172.30.0.21:8090"

url_encode() {
    python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"
}

curl -s "${FETCHSVC}/fetch?url=$(url_encode "https://example.com/page")"
```

The `url` parameter **must** be percent-encoded — an unencoded `?` or `&` in
the target URL will otherwise be parsed as part of the service's own query
string and silently truncate the request.

The response body is the upstream response body. The HTTP status is the
upstream status, so a `404` means the page is missing, not that the service
failed.

## Responses that are not the page

| Status | Body starts with | Meaning |
|---|---|---|
| `403` | `refused:` | The service declined the URL — non-public address, or a scheme other than http/https |
| `502` | `upstream error:` | The service tried and the upstream failed: DNS, TLS, timeout, connection refused |
| `400` | `missing url parameter` | The `url` parameter was absent or empty |
| `405` | `GET only` | A method other than GET was used |

A `403` whose body does **not** begin with `refused:`, or a `curl: (56) CONNECT
tunnel failed, response 403`, is a different thing: that is OpenShell's proxy
refusing, which means the service address is not in the sandbox's network
policy.

## If the service is offline

Symptoms: `curl` exits non-zero with a connection error, or `/healthz` does not
return `200`.

```bash
curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "${FETCHSVC}/healthz"
```

**Tell the operator and stop.** The service is started deliberately from the
host and is expected to be off most of the time:

```
The fetch service is not reachable at 172.30.0.21:8090, so I cannot read
web pages. Start it with:  sandbox.sh --fetch-service
```

Do not try to route around it. There is no alternative path out of the sandbox
for arbitrary hosts — not `WebFetch`, not `curl`, not a proxy. Every attempt
costs turns and ends at the same proxy. `WebSearch` still works if the task can
be served by search results alone.

## Limits

- **GET only.** No POST, no authenticated requests, no file uploads.
- **Public addresses only.** Private, loopback, link-local, multicast, and
  reserved ranges are refused, after DNS resolution and on every redirect hop.
  This is deliberate: the service runs on the host with full network access.
- **8 MB** response cap, **30 s** timeout, **5** redirects.
- **Every request is logged** on the host with the full URL, final URL, status,
  and byte count. Treat the URLs you request as visible.
