# Claude Agent Instructions

OpenShell sandbox configuration for running Claude Code in auto mode inside
rootless Podman containers. Shell scripts, YAML policies, and a Containerfile —
not a Python project. Profiles: `work`, `personal`, `home`, and `codex`; there
is no default. `research` and `fetch-service` are policies only —
`--policy research` and `sandbox.sh --fetch-service`, never `--profile`.

> This file loads into every session in this repo. It holds only what costs real
> time to rediscover — external tool behavior, and places where the obvious
> change is silently wrong. Anything derivable from reading the code belongs in
> a comment at the code, not here.

## Not obvious from the file tree

- `config/site.env` — gitignored, per-machine (this repo is public; no tailnet
  hostnames in git). Deliberately **not** auto-created from
  `config/site.env.example`: silently adopting the template's collector address
  would point a sandbox at a host that may not exist here. Do not add a `cp`
  fallback. Supplies `OTEL_URL`, `PROMETHEUS_URL`, `LOKI_URL`, all required.
  It holds no default profile: that decides which credentials leave the host,
  so it is named per command or the command does not run.
- `policies/local.yaml` — gitignored, for local overrides.
- `docs/configuration-model.md` — a **draft** proposal, not implemented. Do not
  read it as current behavior.
- `tests/test-*.sh` — runnable self-checks, no framework. `make test-unit` runs
  them all; run one directly when iterating. They live outside `scripts/`
  because that directory is on `$PATH`. Each synthesises its own
  `config/site.env` when none exists, so they pass on a fresh clone and in CI.

## Rules where the obvious change is wrong

1. **The sandbox is the security boundary.**
   `--dangerously-skip-permissions` is intentional, as is Codex's
   `--dangerously-bypass-approvals-and-sandbox` on the `codex` profile.
   Network policy (L4/L7), Landlock filesystem, and process isolation replace
   the agent's own permission system. Do not "fix" either flag.
2. **Never hand `policies/*.yaml` to `openshell` directly.** They are templates.
   An unsubstituted `${OTEL_HOST}` is valid YAML, and OpenShell accepts it as a
   literal hostname — the sandbox then silently denies all traffic.
   `render_policy()` substitutes from `site.env` and fails on any leftover
   placeholder.
3. **`render_policy()` renders to a temp file; only `install_policy()` writes
   `~/sandboxes/<name>/openshell-policy.yaml`, and only after the enforcer has
   accepted the policy.** That file *is* the record of what is in force, so a
   path that does not apply a policy cannot change it. Rendering straight into
   the sandbox dir looks harmless and makes the artifact lie — `--refresh` used
   to render the profile default over an applied `fetch-service` policy and
   upload it, dropping blocks the enforcer still allowed. `sandbox-claude.md`
   tells sessions to trust that file. `tests/test-policy-artifact.sh` fails
   if rendering ever writes into the sandbox dir again.
4. **Endpoint host/port derive from the `site.env` URLs** via `urllib.parse`.
   Do not add `*_HOST`/`*_PORT` keys — the same value in two places, free to
   drift, with nothing checking it.
5. **`--profile` applies at build time only** and the script rejects it
   elsewhere. It decides four things at once (`.env` contents, credential
   uploads, rendered policy, which system-prompt fragment is appended) and
   only the create path writes all four; half-applied reads as applied.
   `--recreate NAME --profile <name>` is the only complete way to switch an
   existing sandbox. It is **required** on `--create`, `--recreate`, and on
   every `scode` invocation — reopening an existing sandbox included. Do not
   add a fallback (site.env default, manifest read-back, "personal unless
   Vertex is set"): the two commands that upload wildly different credentials
   must not look identical at the prompt. `tests/test-profile-required.sh`.
6. **Host-owned files upload, never download.** `download_sandbox()` pulls only
   the repo directories named in the manifest, so a session cannot widen its own
   policy or rewrite its repo list by editing its copy.
7. **The dummy OTEL hooks (`python3 -c ""`) must survive settings.json
   stripping.** Claude Code emits no OTEL events for a hook type with no
   registered hook; those entries exist solely to trigger telemetry.
8. **`useradd -d /sandbox` in the Containerfile.** The default `/home/sandbox`
   breaks gitconfig and env sourcing across `sandbox exec` calls.
9. **`host.containers.internal` is unpoliced on every port.** OpenShell cannot
   selectively block ports on the container gateway host, regardless of policy.
   Keep anything that needs port-level policy on its own address, as the
   observability stack is on `172.30.0.10-12`.
10. **Personal profile telemetry is push-only by design.** Collector allowed,
    Prometheus and Loki blocked, so a personal sandbox cannot read work session
    data back. It looks like a missing rule; it is not.
    `validate-profile.sh` asserts the asymmetry. `home` is the variant that
    may read them back — otherwise identical to personal, and every
    credential, env, and prompt decision treats the two as one
    (`personal_profile()` in `lib.sh`, which also covers `codex`). Reaching
    for `== "personal"` instead silently gives home a work sandbox's
    credentials.
11. **No repos are baked into the image.** `knowledgebase` and `standards` are
    cloned on the host and uploaded like any other repo.
12. **`.venv` is excluded in both directions** — host Python 3.14 vs sandbox
    3.13.
13. **`upload_repo()` pre-deletes the sandbox copy.** Without it, re-uploading a
    repo where a path flipped between symlink and directory fails with tar
    `Cannot open: File exists`.
14. **`manifest.json` is written before the sandbox is created, not after the
    repos are cloned.** `init_manifest()` (lib.sh) is called by scode before
    `code` opens the folder and by sandbox.sh before `openshell sandbox
    create`; the repo loop only fills in `.repos`. The file is an input, not
    bookkeeping — the host prompt reads `.profile` out of it, and moving the
    write back into the repo loop hides the profile behind create + clone +
    upload. `tests/test-manifest-timing.sh` fails if it slips.
15. **In `validate-profile.sh`, a missing URL is a FAIL, not a skip** — a
    skipped check reads identically to a passing one. `net_check` needs
    `--max-time`, not just `--connect-timeout`: the latter only bounds the hop
    to the L7 proxy, which always succeeds, so a stalled upstream hangs forever.
16. **Skipping an unchanged repo is the default. `--force`/`-f` always sends.**
    `upload_repo()` rm -rf's the sandbox copy before uploading, so
    `--upload --force` is how edits a session made *inside* the sandbox get
    wiped back to host state. Skipping on "the host has not changed" assumes
    host and sandbox agree — the one thing `--force` exists to fix, which is
    why `--recreate` passes it to both its `--download` and its `--upload`,
    and why `--create`/`--add-repo` set it internally (a freshly cloned repo
    has no context generated yet). The default takes the other bargain: no
    gh/Jira calls, and skip any repo untouched since
    `.repos[<name>].last_upload`, because upload is a full tar with no delta
    and the reference repos dominate the payload. That mtime walk must
    keep excluding `.git`, `.git/index` and `.git/index.lock`: `git status`
    rewrites exactly those three and nothing else, so any editor or shell
    prompt polling status makes every repo look modified on every run. The
    rest of `.git` is still walked, which is what keeps staging, commits and
    branch switches detected. Relatedly, do not add
    write-only-if-changed logic to the context writers to keep repos "clean":
    the open-prs debounce reads `open-prs.json`'s mtime and would stop
    advancing. `tests/test-upload-skip.sh` and `tests/test-open-prs.sh` fail if
    either returns.
    `--download` is the mirror image, and asymmetric on purpose.
    Nothing on the host can see the sandbox, so the walk runs there, over
    `openshell sandbox exec` — one exec for every repo, because the walk is
    cheap and the round trip is not. It compares against the LATEST of
    `last_upload`/`last_download`, both of which mark a moment the two copies
    agreed. A repo counts as clean only on a positive empty walk: the `WALKED`
    sentinel is what separates "found nothing" from "the exec never ran", and
    without it a dead gateway reads as "nothing changed". The fail-safe runs
    the other way from the upload side — a wrongly skipped upload costs one
    redundant tar, a wrongly skipped download loses whatever the session did.
    `download_sandbox()` is the other half of the same rule: it rsyncs
    `--no-times --checksum`, so a downloaded file the sandbox never changed
    keeps its host mtime. `openshell sandbox download` does not preserve
    mtimes, so a plain `rsync -a` rewrote every file and left the repo newer
    than `last_upload` — and edit-in-sandbox, download, upload is the usual
    pattern, so the upload had nothing left to skip. `--checksum` alone is not
    enough: for matching content rsync still does an attribute-only mtime
    update. Measured with rsync 3.4.1: `-a --delete` touches every path of an
    identical tree, `-a --checksum --delete` touches every path,
    `-a --no-times --checksum --delete` touches none.
17. **Profile name, policy filename, and system-prompt fragment are one
    word.** `--profile home` renders `policies/home.yaml` and appends
    `config/sandbox-claude.d/home.md` if it exists. Adding a profile means
    adding a policy of the same name, and nothing maps between them. The
    prompt fragments are additive: a section that only some profiles should
    see goes in `sandbox-claude.d/<profile>.md`, never in the base with a
    subtractive `sed`. The base is what every profile receives verbatim, so
    two things stay out of it: `## Jira` (work tooling in a personal sandbox)
    and reading telemetry back (personal is push-only, and a prompt that says
    to query Prometheus produces a session arguing with a 403). The base
    mentions OTEL egress and says outright that silence here means no
    read access, so a session does not infer capability from the gap.
    `work.md`, `home.md` and `codex.md` therefore carry an identical
    `## Reading telemetry back` section — three copies of fifteen lines of
    prose, cheaper than a second include mechanism in `upload_config()`. It is
    last in all three files, because the test compares them by tailing from
    the heading; `codex.md`'s own section goes before it for that reason.
    `tests/test-profile-required.sh` fails if either section returns to the
    base, and diffs the fragments so they cannot drift apart.

18. **No signing key goes into a sandbox, and no `ssh-keygen` to use one.**
    Nothing commits in a sandbox. `upload_config()` ships `.gitconfig` and not
    `user.signingkey`'s target — on this host that path is the unencrypted
    PRIVATE key, and it was landing in every sandbox on every profile. The
    uploaded gitconfig keeps `commit.gpgsign=true` pointing at a path that no
    longer resolves, so a commit fails loudly rather than landing unsigned.
    A sandbox commit erroring on a missing key or a missing `ssh-keygen` is
    the design working. The two attractive "fixes" — restoring the key upload,
    or adding `openssh-client` to the Containerfile — both re-open it.
    `tests/test-scode-naming.sh` needs `GIT_CONFIG_GLOBAL=/dev/null` for the
    same reason every other committing test does.

19. **The `codex` profile swaps the agent, and the swap has to go both ways.**
    `policies/codex.yaml` is `home.yaml` with `anthropic-api` replaced by
    `openai-api` (`chatgpt.com`, `api.openai.com`, `auth.openai.com` — the
    provider on a ChatGPT sign-in, the provider on an API key, and the OAuth
    issuer; each missing host breaks a different operation as an unexplained
    403). Leaving Anthropic reachable "so Claude still works there" is the
    tempting change and the wrong one: that is a `home` sandbox with an extra
    CLI in it, and nothing in a running session says which agent it is talking
    to. `validate-profile.sh` and `tests/test-profile-required.sh` both assert
    the swap in both directions.
    Three things it deliberately does **not** do, all of which look like
    oversights:
    - **No credential upload and no preservation.** `/sandbox/.codex/auth.json`
      is written by signing in inside the sandbox and is gone on `--recreate`.
      Claude's OAuth survives only because `download_claude_state()` explicitly
      carries it, and `download_codex_state()` (gotcha 23) deliberately does
      not do the same for `auth.json`: on `work` the host ships it, so a
      preserved copy would let a stale key beat a rotated one. Signed out on a fresh
      sandbox is the expected state, and `validate-profile.sh` reports it as
      such. The browser flow binds `127.0.0.1:1455`, so device code is not a
      preference — it is the only flow that can complete in here.
    - **No login detection in the wrapper.** Codex already does it: `run_main`
      (`tui/src/lib.rs`) calls `should_show_onboarding()`, which returns true
      on `LoginStatus::NotAuthenticated`, and the auth step it then shows
      offers "Sign in with Device Code" for exactly this case. That check runs
      *before* resume selection, so the `codex resume --last` branch is covered
      too. A probe in the wrapper would duplicate a state machine that changes
      upstream. Note there is no `/login` slash command to fall back on —
      `tui/src/slash_command.rs` has `Logout` and no login variant — so the
      onboarding screen is the only way in, which is why it must not be
      bypassed.
    - **No second copy of the system prompt.** `upload_static()` writes
      `/sandbox/source/CLAUDE.md`, which Codex does not read.
      `harness-wrapper.sh` symlinks `$CODEX_HOME/AGENTS.md` at it on every
      launch — that path is loaded unconditionally regardless of cwd
      (`codex-home/src/instructions/mod.rs`), and relinking each time is what
      keeps it correct across `--refresh`. The symlink is still the right
      mechanism because the target is repo content, not host config.
      A `.codex/` directory upload is safe (gotcha 20); the mechanism here is
      the symlink because the target is repo content, not host config.

20. **`openshell sandbox upload` merges; it does not clobber.** The pre-delete
    that gotcha 16 describes belongs to `upload_repo()`, which `rm -rf`s the
    destination itself. The bare `openshell sandbox upload` calls in
    `upload_config()` do not: OpenShell streams a tar and runs
    `tar xf - -C <dest>` (`crates/openshell-cli/src/ssh.rs`), which overwrites
    the entries in the archive and leaves everything else alone. That is why
    `.config/git/ignore` and `.config/gws` coexist despite both uploading a
    `.config` directory, and it is what makes the Codex upload below safe.

21. **Codex telemetry config uploads on every profile: three named files plus a generated
    `config.toml`.** `upload_config()` ships `hooks.json` and `observe-hook.py`
    on every profile, and `auth.json` only when `! personal_profile`.
    Never a mirror of `~/.codex/`: `sessions/`, `history.jsonl` and the
    `*_N.sqlite` files are transcripts of every Codex conversation on the host
    across every project, and shipping those into a work sandbox pushes
    personal content in exactly the direction the profile split exists to
    stop. The sandbox's own `state_*.sqlite` and rollouts are also what
    `claude-dashboard` reads to discover local Codex sessions in there, so a
    host copy would be actively wrong — and by gotcha 20 they survive the
    upload untouched.
    - **`auth.json` ships on work and not on codex.** It holds
      `OPENAI_API_KEY`. Work sandboxes already carry work credentials (gws,
      Vertex, Jira), so one more is not a new class of thing, and signing in by
      hand in every sandbox is friction. The `codex` profile keeps gotcha 19's
      no-credential behaviour: it signs in inside.
    - **`hooks.json` and `observe-hook.py` prefer the adjacent
      `claude-otel-stack/codex/` checkout.** `CODEX_OTEL_SOURCE_DIR` can point
      elsewhere; the `$HOME/.codex/` fallback is accepted only when the hook
      contains the current timestamp/resource-identity fields. This prevents a
      stale host copy from silently producing token data without session-state
      data. Hooks are uploaded on `codex` too; only `auth.json` is work-only.
    - **`config.toml` is generated, never the host's file.** The host's own
      file can carry MCP server commands and `sandbox_permissions` entries
      built around host paths, meaningless in here, and its `[otel]` table (if
      any) points at the host's own collector — typically `localhost`,
      unreachable from in here. So `upload_config()` writes a fresh one
      instead: the host's `model =` line, if it has one (Codex has no
      per-profile default the way `harness-wrapper.sh` hardcodes one for
      Claude on personal/home, so leaving this off drops the host's choice
      silently), plus a freshly-generated `[otel.exporter.otlp-http]` table
      pointed at `$OTEL_URL` (the same sandbox-correct address used for
      `OTEL_EXPORTER_OTLP_ENDPOINT`, gotcha 13) with `protocol = "binary"`
      (OTLP-over-HTTP-protobuf; `codex logout` rejects anything but `"binary"`
      or `"json"` here). Unlike the `hooks.json` pipeline above, Codex's own
      OTLP client does not read `OTEL_EXPORTER_OTLP_ENDPOINT` from the
      environment — confirmed empirically: an `[otel.exporter.otlp-http]`
      table with no `endpoint` key fails config load with `missing field
      "endpoint"` rather than falling back to the env var. This enables
      Codex's own native cost/token-usage telemetry; the hooks.json /
      observe-hook.py pipeline above is unrelated and unaffected.
      `CODEX_STATE_KEEP` (gotcha 23) still preserves the sandbox's own
      `config.toml` across `--recreate` and that preserved copy still wins
      (upload order: `upload_config()` then `upload_codex_state()`, and
      gotcha 20's merge means the later write wins) — so a model changed
      from inside the sandbox survives a recreate the same way it always did,
      but so does a stale `$OTEL_URL` from before the collector moved. Only a
      sandbox with no prior `.codex/` state gets the freshly-computed one.
    - **`policies/work.yaml` carries `openai-api` alongside
      `vertex-ai-inference`**, not instead of it: a work sandbox runs both
      agents. This is the one place the codex-profile swap rule (gotcha 19)
      does not apply, and `bin/validate-profile.sh`'s `openai_profile()` plus
      `tests/test-profile-required.sh` assert the membership for work, codex,
      home and personal in both directions.

22. **`--harness claude|codex` picks the agent, one dtach socket each.**
    Valid with `--create`, `--connect` and `--recreate`, and on `scode`.
    `connect_sandbox()` passes the harness to `/sandbox/bin/harness-wrapper.sh`
    as `$1`; the wrapper derives `SOCKET=/sandbox/.dtach-${HARNESS}`, so Claude
    and Codex can both be live in one sandbox and each `--connect` reattaches
    to its own.
    - **`--connect` uploads `bin/` unconditionally.** `connect_sandbox()` execs
      the wrapper by absolute path, so a sandbox whose copy is older than the
      script either fails with a bare `No such file or directory` or ignores an
      argument it does not know and silently starts the wrong agent. Two small
      files; do not make it conditional.
    - **With no harness named, the wrapper asks.** The prompt is bounded by
      `HARNESS_PROMPT_TIMEOUT` (5s) and falls back to a computed default.
      `read -t` returns non-zero and leaves the variable **empty** on timeout —
      the `-i` prefill is not retained — so `${answer:-$default}` is load
      bearing, not defensive: trust `-i` and a timed-out prompt launches
      nothing. The same path covers a non-tty stdin, which hits EOF at once.
    - **`manifest.json` `.harness` is the only store, and it is host-side.**
      `--recreate` deletes the remote sandbox, never `~/sandboxes/<name>`, so
      the remembered harness survives a rebuild with no preservation path and
      no round trip — host tooling can also read it without entering the
      container. Nothing is written inside the sandbox. **A session cannot
      write it back** (gotcha 6), which is the deliberate cost: a harness
      picked at the wrapper's prompt applies to that launch only, and
      `--harness` is what changes the memory. Do not add a container-side
      last-used file to "fix" that — two stores drift, and the prompt is the
      deviation path by design.
    - **Unlike `--profile`, `--harness` IS defaulted from the manifest.**
      Gotcha 5 requires the profile every time because it decides which
      credentials leave the host; the harness decides nothing of the sort, so
      the same argument does not carry over.
    - **Two channels into the wrapper, meaning different things.** An explicit
      `--harness` goes as argv and skips the prompt — the decision is already
      made. The manifest's value goes as `$HARNESS_DEFAULT` and only
      preselects. Collapsing them into one would either stall an explicit
      choice for the timeout or make the remembered value unoverridable.
    - **The default is never profile-based.** In precedence: exactly one live
      dtach socket (reattaching to the running session is the reason to ask at
      all), then `$HARNESS_DEFAULT`, then `HARNESS_FALLBACK` (claude). Two live
      sockets is not a signal — both agents are up and neither is the better
      guess. The profile decides which credentials and which network policy a
      sandbox got, not which agent the human wants this time: `work` carries
      both Anthropic and OpenAI egress and runs either, which is what made a
      profile-keyed default unstatable. `tests/test-connect-harness.sh` drives
      the precedence against real AF_UNIX sockets and asserts `default_harness`
      does not read `$SANDBOX_PROFILE`.
    - **`default_harness` emits `"<harness> <reason>"` from one set of
      branches**, and the prompt shows the reason (`[codex - remembered]`).
      Recomputing the reason in a second function drifts from the chooser and
      reports a value the chooser rejected. Keep them together.
    - **The harness is a flag, not a positional.** A positional would collide
      with sandboxes actually named "claude" or "codex", including through
      `--recreate`, which re-execs `--connect "$SANDBOX_NAME"`. A flag also
      works on `--create` and `--recreate`, which have no positional to spare.
    - **Codex launches `codex resume` unconditionally**, with no check for
      existing sessions. Its picker starts a new session as readily as it
      resumes one and works with none recorded, so testing for
      `/sandbox/.codex/sessions` first buys nothing. It carries
      `--dangerously-bypass-approvals-and-sandbox` **and**
      `--dangerously-bypass-hook-trust`: every hook in the sandbox was uploaded
      from the host by `upload_config()`, so the trust gate has no untrusted
      hook to catch and only costs a prompt on the observe-hook that reports
      state to claude-dashboard. There is **no `--yolo`** in codex 0.152.0 —
      the long flags are the flags, and the test asserts it has not crept in.
    - **The `AGENTS.md` symlink is keyed on the harness, not the profile.** Any
      profile can run Codex, so gating it on `SANDBOX_PROFILE == codex` leaves
      a work sandbox's Codex without the system prompt.

23. **Codex conversation history survives `--recreate`.**
    `download_codex_state()` / `upload_codex_state()` mirror the Claude pair.
    `codex resume` needs *both* halves — the `threads` table in the state
    database to list sessions, and the rollout jsonl each row's `rollout_path`
    points at — so preserving one without the other restores nothing.
    `rollout_path` is stored absolute (`/sandbox/.codex/sessions/...`) and that
    path is identical in the rebuilt container, so nothing is rewritten.
    - **One download of the whole `~/.codex`, filtered on the host.** The state
      databases are schema-versioned (`state_5.sqlite`, and a machine can carry
      several), so there is no static name to ask for. Filtering where a glob
      works beats guessing names over the wire.
    - **A database travels with its `-wal`, never with its `-shm`.** A
      `state_5.sqlite` moved without the write-ahead log is nearly empty —
      measured in a live sandbox at 4KB of database against 2.1MB of log. The
      `-shm` is a rebuildable index SQLite regenerates from the `-wal`, and
      SQLite says not to move it between machines: a stale one is worse than
      none. `tests/test-codex-state.sh` asserts both directions.
    - **`CODEX_STATE_KEEP` is an allowlist.** `sessions/`, `history.jsonl`,
      `session_index.jsonl`, `config.toml`, plus the databases. Everything else
      — `auth.json` (above), `thread-writer-locks/`, `shell_snapshots/`,
      `tmp/`, `installation_id` — stays behind. Note this is the *opposite*
      shape from the `~/.claude` upload in `upload_config()`, which is a
      denylist of `rsync --exclude`s: what a sandbox produces is open-ended, so
      naming what to rescue is safer than naming what to drop.
    - **The filter reports failure on an empty source.** Otherwise an empty
      `~/.codex` stages an empty upload over the real one on the next create.
    - **`codex_state_filter()` is split out of the download** purely so
      `tests/test-codex-state.sh` can drive it against a fake tree; the
      download needs a live sandbox, the filtering does not.

## Settled, do not re-evaluate

- **screen and tmux were tested and rejected** for session persistence — both
  mangle Claude Code's TUI through their terminal emulation layers. `dtach`
  only, one socket per harness at `/sandbox/.dtach-<harness>`, requires
  `/dev/pts` in policy `read_write`. See
  `knowledgebase/containers/terminal-multiplexers-in-sandboxes.md`.
- **`.claude.json` and `.credentials.json` are both required** to preserve
  OAuth across `--recreate`. See
  [knowledgebase: oauth-tokens](https://github.com/jewzaam/knowledgebase/blob/main/claude-code/oauth-tokens.md).
- **Sandbox names are hashed** because OpenShell enforces a 19-char limit (DNS
  label: 19+2+19+2+19=61 < 63). `short_name()` produces `sb-<12-char-md5>`.
- **`--ref pr/N` checks out through `gh pr checkout`**, so the branch is the
  PR's own head ref with a real upstream — a `git fetch pull/N/head:pr-N`
  branch has none, and reads as local-only to anything watching the checkout.
  The sandbox is still named `<repo>-pr-N`; only the branch changed. The
  refs/pull fetch remains as the no-gh/no-network fallback.
- **Context generation detects PRs from git, not manifest.** `generate_repo_context()`
  runs `gh pr view <arg>` on the host, where `<arg>` is the branch name, or the
  number when the branch is a fallback `pr-N` or its upstream is
  `refs/pull/N/head` (how `gh` records a fork PR — the head ref lives in the
  fork, so the name means nothing in the base repo). Manifest ref is updated to
  match, not the other way around. Switching branches locally and re-uploading
  regenerates context automatically.
- **Context files are separate.** `pr-context.md` (PR metadata only),
  `jira-context.md` (linked Jira issues), `open-prs.json` (all open PRs,
  structured). Never combined. `open-prs.json` is generated by
  `scripts/format-open-prs.py <org/repo>` — bot PRs are one-line entries,
  human PRs include files changed, base branch, merge state.
- **A gh failure is not evidence about the PR.** `gh pr view` exits 1 both for
  "no such PR" and for a 502, and the "no such PR" branch deletes
  `pr-context.md` and `jira-context.md`. `gh_pr_view_json()` returns 2 only
  when gh actually answered (`no pull requests found` / `Could not resolve`);
  anything else is 1 and the existing files are kept.
- **Only `gh pr checkout` retries** (`GH_RETRY_ATTEMPTS`, default 3, delay
  doubling from `GH_RETRY_DELAY`, default 2s). It decides what code is in the
  sandbox and runs once per repo at create time. Context generation runs on
  every upload for every repo, so a backoff there multiplies: with GitHub
  down, retrying `gh pr list` alone made a multi-repo upload take 3x as long
  for data that is optional. `tests/test-gh-retry.sh` asserts the one-call
  ceiling during an outage.
- **`open-prs.json` is always written for a GitHub repo, and is debounced.**
  No open PRs is `{"prs": []}`, not a missing file — absence used to mean
  "none", "gh failed", and "not GitHub" at once. `gh pr list --json files` is
  the slowest call in an upload and runs per repo, so a file younger than
  `OPEN_PRS_TTL_MINUTES` (default 60) is reused; set it to 0 to force. The
  debounce reads the file's own mtime, so the file must be written on every
  fetch. A failed fetch writes `fetch_error` + `fetch_error_at` into the file
  (keeping any real `prs` already there) so the failure is debounced like a
  success — these failures are repo-pinned, and a repo gh cannot read would
  otherwise burn a doomed call on every upload forever.
- **`scode` accepts Jira URLs.** `scode https://...atlassian.net/browse/KEY-123`
  fetches issue context into `jira-context.md`, creates a no-repo sandbox named
  `key-123` (lowercased).
- **`scode` accepts multiple PR URLs.** `scode PR_URL1 PR_URL2` for multi-repo
  review. Each becomes a `--repo`/`--ref` pair; sandbox named after first PR.
- **`ANTHROPIC_DEFAULT_{HAIKU,OPUS,SONNET}_MODEL` are stripped from the
  uploaded `settings.json` for every profile**, by
  `scripts/strip-settings.py`. A host pins models for host reasons; in a
  sandbox available models may differ.  Pinning model is not required.
- **Personal and home set `--model claude-opus-5[1m]`** in the sandbox
  `harness-wrapper.sh`, off `$SANDBOX_PROFILE` from `/sandbox/.env`. Not off
  manifest.json — that is uploaded by `upload_static()` and used to lose the
  race on a first create, silently starting personal sessions on the default
  model. `.env` carries `SANDBOX_PROFILE` for every profile, not just the
  credential-less ones: `validate-profile.sh` cannot tell home from personal
  without it, and `sandbox.sh` folds it into `OTEL_RESOURCE_ATTRIBUTES` as
  `sandbox.profile`.
- **`/sandbox/.env` is host knowledge; `config/bashrc` is container policy.**
  What only the host can know — credentials, collector address, which machine
  and sandbox this is, and the `OTEL_RESOURCE_ATTRIBUTES` assembled from them —
  is written into `.env` at create time. How the agent behaves in here —
  telemetry toggles, exporters, intervals, log detail — lives in `config/bashrc`
  and is never captured from the host env, so a host preference cannot silently
  change a sandbox. Both halves have to be inherited, not sourced by a
  launcher: `bin/claude.env` held the policy and only `harness-wrapper.sh` read
  it, so a bare `claude` came up with an endpoint and telemetry off; the
  attributes were assembled there too, so every review-orchestrator sub-agent
  reported with no identity at all.
  `docs/environment-variables.md` has the full chain and the evidence that
  Claude Code strips `OTEL_*` from the env it hands to tool subprocesses.

## OpenShell Policy Gotchas

Hard-won, and referenced by number from `sandbox.sh` and
`docs/configuration-model.md` — do not renumber, simplify, or remove:

1. `binaries: [{ path: "*" }]` does NOT match all paths. Use `{ path: "/**" }`.
2. `access: write` is not valid. Valid: `read-only`, `read-write`, `full`. Invalid values silently deny.
3. `*.example.com` matches one subdomain level. Use `**.example.com` for multi-level.
4. `/sys` must be in `filesystem_policy.read_only` or `getifaddrs` fails (Node.js).
5. `sandbox connect` does not accept `-- COMMAND`. Use `sandbox exec --tty`.
6. `sandbox create` with `-- COMMAND` hangs on podman driver. Create in background, poll, use `exec`.
7. `--upload` on `sandbox create` is unreliable. Use `sandbox upload` after creation.
8. `sandbox upload` preserves symlinks as-is. Resolve with `rsync -rL` before uploading.
9. `sandbox exec` stdin pipe is limited to 4MB.
10. OpenShell overwrites `/sandbox/.bashrc` during `sandbox create`. Re-upload after creation.
11. `sandbox upload` treats destination as parent directory. Uploading `foo` to `/sandbox/` creates `/sandbox/foo/`.
12. `sandbox upload` of a single file to a directory replaces the directory contents. Upload the parent directory instead (e.g. `upload bin/ /sandbox/` not `upload bin/file /sandbox/bin/`).
13. All traffic goes through OpenShell's HTTP/1.1 CONNECT proxy. gRPC (HTTP/2) cannot traverse it. Use OTLP HTTP (`http/protobuf` on port 4318) instead of gRPC (port 4317) for telemetry.
14. Policies can be hot-updated on running sandboxes: `openshell policy set --policy <file> <name>`.
15. `host: "**"` rejected by L7 validation — "host wildcard matches all hosts; use specific patterns like `*.example.com`". No match-all host wildcard supported.
16. TLD wildcards (`*.com`, `*.org`) rejected — "TLD wildcard not allowed; use subdomain wildcards like `*.example.com` instead".
17. `openshell policy set` returns exit 0 even when L7 validation fails. Policy application is async. Check `openshell policy list <name>` for `Failed`/`Loaded`/`Effective` status. `sandbox.sh --policy` handles this automatically.
18. OpenShell injects `ALL_PROXY=http://10.200.0.1:3128` and lowercase `http_proxy`/`https_proxy`/`no_proxy` into sandbox processes. `ALL_PROXY` overrides user-set `HTTPS_PROXY`. Must unset `ALL_PROXY` and set lowercase variants to override.
19. `host.containers.internal` resolves to `169.254.1.2` but is NOT directly reachable from sandbox. All traffic forced through L7 proxy at `10.200.0.1:3128`. Cannot bypass the proxy for direct host access.
20. `sandbox exec` connections drop during idle. No gRPC keepalive configuration exposed. Workaround: background ENQ keepalive in the exec bash command.
21. `openshell sandbox exec` requires `--name` flag. The sandbox name is not positional for exec. Pattern: `openshell sandbox exec --name "$name" "${GW_FLAG[@]}" -- command`.
22. A policy endpoint needs both `protocol: rest` and `enforcement: enforce` for CONNECT to work. Omitting them (e.g. for intended L4-only passthrough) forwards an absolute-URI `GET` to that host:port but returns 403 on `CONNECT` to the same host:port. Match every working endpoint in `policies/` — both fields are always present together.
23. The proxy resets any request whose path contains `%2f` or `%2F`, so **no scoped npm package can be installed from inside a sandbox**. Measured against `registry.npmjs.org` with the `npm-readonly` block in force: `/express` → 200, `/@openai/codex` → 200, `/@openai%2fcodex` → connection reset (curl exit 56, `%{http_code}` 000). npm always encodes the scope separator, so `npm install @scope/pkg` fails with `ECONNRESET ... socket hang up` and reads as a flaky network. Every scoped tool has to be baked into the Containerfile. The image build runs on the host and is not subject to this.

## Other gotchas

- **`yq` in the image is the kislyuk build (pip), not mikefarah/yq (Go).**
  Filters are jq syntax. The two share a name; the expression language differs.
- **Bash `$()` strips trailing newlines.** Building `.env` content with
  `printf '%s=%q\n'` inside `$()` loses the final newline — append `$'\n'`
  outside the substitution.
- **Debian apt is reachable but cannot install system-wide.** No `sudo`, `/usr`
  is read-only, `/var` is in neither filesystem list. Download-and-extract to
  `/tmp` works; the recipe is in `config/sandbox-claude.md`. The point is
  discovery — find a package, prove it, then add it to the Containerfile.

## Reboot Recovery

Two things break after a host reboot:

1. **Rootless-netns is stale.** Pasta's rootless network namespace references
   interfaces from the previous boot. Run `scripts/reset-rootless-netns.sh`
   before starting the gateway.
2. **Sandbox JWTs may be expired.** The gateway now mints `exp=0` tokens, so new
   sandboxes need nothing. For older ones, `scripts/mint-sandbox-tokens.sh`
   re-mints every errored sandbox.

## Development Workflow

1. Edit files
2. `make check` — shellcheck (warnings and up) + the `tests/` self-checks. Same
   two targets CI runs, so a green local run is a green PR.
3. `make build` if Containerfile, `bin/`, or `config/` changed
4. Test with `scripts/sandbox.sh --create test`
5. No rebuild needed for policy-only or env var changes
6. `scripts/sandbox.sh --refresh` pushes config changes without rebuilding

## Standards

- Shell scripts: `set -euo pipefail`, no semicolons for chaining (use `&&`)
- CLI output: `~/source/standards/cli/conventions.md` § Output — sentence case,
  status at column 0, detail lines indented 4, `⊘` for skipped. openshell prints
  its own `Uploading ...` / `✓ Upload complete` around every transfer, so this
  repo announces only what openshell cannot: why a transfer was skipped.
- Makefile: follows `~/source/standards/build/makefile.md` — `check` is the
  default goal; `test-*` targets are the gate. The standard's Python targets
  (`test-format`, `test-typecheck`, `test-coverage`, `install-dev`) have no
  meaning in a shell repo and are deliberately absent.
- Workflows: `~/source/standards/build/github-workflows.md` — `test` runs
  `make test-unit`, `quality` runs `make test-lint`. Both call Make, never
  duplicate the commands.
- Naming: `~/source/standards/common/naming.md`
- Local config: `~/source/standards/common/local-config-split.md`
- Container tool: podman (not docker). `CONTAINER_TOOL ?= podman` in Makefile
- License: Apache 2.0
