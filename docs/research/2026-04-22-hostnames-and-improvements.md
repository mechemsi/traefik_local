# Local DNS + DX research — 2026-04-22

Consolidated findings from three parallel research passes covering:
1. WSL2 + Windows hostname resolution for `*.localhost`.
2. Automatic local domain assignment strategies.
3. Traefik v3 DX improvements worth adding next.

Sources are cited inline.

## TL;DR

- **The Windows `hosts` file most likely does not need editing** for this
  setup. Modern browsers (Chrome, Firefox, Edge) resolve any `*.localhost`
  to loopback themselves per RFC 6761 §6.3, without consulting DNS or the
  hosts file.
- **Automatic hostname-per-project is a one-line change** to
  `docker-compose.yml`:
  `--providers.docker.defaultRule=Host(\`{{ normalize .Name }}.localhost\`)`.
  Every labeled container then gets `<container-name>.localhost` for free.
- **Patch Windows past the November 2025 cumulative rollup** to dodge the
  KB5066835 loopback HTTP/2 regression.
- A short ranked list of other improvements (dashboard BasicAuth, access
  logs, anchor-based multi-service overrides, mkcert HTTPS) is at the end.

---

## 1. Hostname resolution in WSL2 + Windows 11

### Does `*.localhost` just work?

**Yes, in the browser — no, in the Windows OS resolver.**

- Chrome has hardcoded `localhost` and `*.localhost` to loopback since
  v42, per RFC 6761 §6.3. Firefox and Edge have since matched. The OS
  resolver is never consulted.
  Refs: [Chromium issue 41175806](https://issues.chromium.org/issues/41175806),
  [Microsoft Learn — .localhost TLD](https://learn.microsoft.com/en-us/aspnet/core/test/localhost-tld),
  [Mozilla bug 1433933](https://bugzilla.mozilla.org/show_bug.cgi?id=1433933).
- Windows' own resolver only hardcodes plain `localhost`, not wildcards.
  Non-browser Windows tools (curl.exe, PowerShell `Invoke-WebRequest`,
  some .NET clients) may return NXDOMAIN for `foo.localhost`. For a
  browser-first workflow this never matters.
- Inside WSL, glibc NSS treats `.localhost` as loopback at the resolver
  level, so `curl http://foo.localhost` works from a WSL shell too.

### Windows → WSL2 port reachability

Two mechanisms, both work:

1. **Default NAT mode (`localhostForwarding=true`)**: WSL2's vsock
   forwarder mirrors any `0.0.0.0:<port>` bind inside WSL onto Windows
   `localhost:<port>`. This works whether docker runs as Docker Desktop
   or natively in WSL.
2. **Mirrored mode (`networkingMode=mirrored`)**: opt-in via `.wslconfig`;
   Windows and WSL share the same loopback, better IPv6/LAN/VPN story.
   Still opt-in on current Windows 11 builds.

Refs: [Microsoft Learn — WSL networking](https://learn.microsoft.com/en-us/windows/wsl/networking),
[Microsoft Learn — wsl-config](https://learn.microsoft.com/en-us/windows/wsl/wsl-config).

### Known regression to dodge

The **October 2025 Windows cumulative update (KB5066835)** broke loopback
HTTP/2 — `ERR_HTTP2_PROTOCOL_ERROR` / `ERR_CONNECTION_RESET` on
`localhost` and `127.0.0.1`. Fixed in the **November 2025 monthly
rollup**. If loopback connections are flaky, check Windows Update first.

Refs:
[gbhackers — Windows 11 October update disrupts localhost](https://gbhackers.com/microsoft-windows-11-october-update/),
[borncity — KB5066835 notes](https://borncity.com/win/2025/10/16/windows-11-24h2-25h2-localhost-issues-after-october-2025-update-kb5066835/),
[cristianthous — HTTP/2 loopback](https://cristianthous.com/windows-11-october-update-breaks-localhost-http-2-127-0-0-1-connections).

### When hosts edits are actually needed

Only if you leave `.localhost` behind:
- Custom TLDs: `.test`, `.dev`, `.local`, `.internal`.
- Bare names: `myapp`, `traefik-dashboard`.
- Non-browser tools on Windows that don't special-case `.localhost`.

Windows hosts does not support wildcards — each name needs its own line.
**Conclusion:** stick to `<app>.localhost` and skip this whole problem.

### Fallback if `.localhost` ever fails

Use `sslip.io` or `nip.io`:
`whoami.127.0.0.1.nip.io` → resolves to 127.0.0.1 via public DNS, no
hosts edit, no local DNS server.

Caveats:
- Cookies scope to the registrable domain (`nip.io`), so cross-project
  cookie isolation is worse than `.localhost`.
- No wildcard TLS certs issued (since sslip.io's 2015 revocation
  incident). HTTPS must be per-host via Let's Encrypt HTTP-01.
- Service outage = all your dev hostnames fail.

Refs: [sslip.io](https://sslip.io/), [nip.io](https://nip.io/),
[sslip.io wildcard cert history — issue #6](https://github.com/cunnie/sslip.io/issues/6).

### Hosts-file automation (if you ever need it)

- [`hostctl`](https://github.com/guumaster/hostctl) — Go, cross-platform,
  profile-based, MIT. Available via winget/scoop/choco.
- **PowerToys Hosts File Editor** — built-in Windows GUI.
- [Acrylic DNS Proxy](https://mayakron.altervista.org/) — supports true
  wildcards via regex. **Broken on WSL2** per
  [microsoft/WSL#5214](https://github.com/microsoft/WSL/issues/5214) —
  avoid.

---

## 2. Automatic domain assignment

### The one-line win

Traefik's Docker provider supports a Go-templated default rule. Add this
to the hub's `command:` block:

```
- --providers.docker.defaultRule=Host(`{{ normalize .Name }}.localhost`)
```

Now any container with just `traefik.enable=true` is automatically routed
at `<container-name>.localhost`. Per-container Host() labels only needed
when you want a non-default name.

Variant that uses compose service + project name
(Orbstack-style `service.project.localhost`):

```
- --providers.docker.defaultRule=Host(`{{ index .Labels "com.docker.compose.service" }}.{{ index .Labels "com.docker.compose.project" }}.localhost`)
```

Refs:
[Traefik Docker provider reference](https://doc.traefik.io/traefik/reference/routing-configuration/other-providers/docker/),
[Traefik community — defaultRule template](https://community.traefik.io/t/template-for-defaultrule-when-using-portainer-and-stacks/9611).

Effect on `snippets/docker-compose.traefik.yml`: the router `rule=` and
service-level label block become optional. You still need
`traefik.http.services.<name>.loadbalancer.server.port=${APP_PORT}`
because Traefik cannot auto-guess the upstream port when a container
exposes multiple, but the hostname is free.

### Wildcard-loopback DNS services — quick comparison

| Service | Status (2026) | IPv6 | HTTPS certs | Notes |
|---|---|---|---|---|
| **sslip.io** | Active; runs nip.io too | Yes | Per-host LE only | Pick this if you need one |
| **nip.io** | Alias of sslip.io | IPv4 only | Same | Memorial for original maintainer |
| **localtest.me** | Active, static | Yes (::1) | Per-host LE only | Simplest; no IP-embedding |
| **vcap.me** | Legacy Cloud Foundry, archived | Unclear | None | Avoid |

### What ddev / Orbstack do (and whether to copy)

- **ddev**: `*.ddev.site` is a real public A record → 127.0.0.1. Falls
  back to hosts-file edits via the privileged `ddev-hostname` binary.
  HTTPS via bundled `mkcert`.
- **Orbstack**: custom in-VM DNS resolver answering `*.orb.local`,
  registered with macOS so the whole OS resolves it. Auto-detects each
  container's web port. Breaks in Sequoia mDNS and VPN edge cases.

**Worth copying?** The `service.project.localhost` naming, yes (one
line, via `defaultRule`). The resolver plumbing, no — it's
platform-specific and fragile, and unnecessary because `.localhost` is
already special-cased in browsers.

### dnsmasq / Acrylic

Only useful if:
- You need non-browser clients (Postman-native, curl on Windows) to
  resolve your dev hostnames, or
- You need containers to resolve each other's dev hostnames.

For a browser-driven workflow, both are overkill. Acrylic specifically
is [known-broken on WSL2](https://github.com/microsoft/WSL/issues/5214).

---

## 3. DX improvements — ranked shortlist

Each improvement links to where it would live.

### 3.1 Auto-hostname via `defaultRule` — XS

Covered above. Single line in `docker-compose.yml`. Highest bang/buck.

### 3.2 Dashboard BasicAuth — XS

Kills the "dashboard is open to the world" caveat in the README. Drop
`--api.insecure=true` and the 8080 port, add a BasicAuth middleware to
the dashboard router:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.dashboard.rule=Host(`traefik.localhost`)
  - traefik.http.routers.dashboard.service=api@internal
  - traefik.http.routers.dashboard.entrypoints=web
  - traefik.http.routers.dashboard.middlewares=dashboard-auth@docker
  - traefik.http.middlewares.dashboard-auth.basicauth.users=admin:$$2y$$05$$…
```

Generate the hash: `htpasswd -nB admin | sed -e 's/\$/\$\$/g'` — `$`
must be doubled inside compose.
Ref: [Traefik BasicAuth docs](https://doc.traefik.io/traefik/reference/routing-configuration/http/middlewares/basicauth/).

### 3.3 Access logs to stdout — XS

Currently a 404 on `whoami.localhost` shows nothing useful in
`docker logs traefik`. Two new flags fix that:

```yaml
command:
  - --log.level=INFO
  - --accesslog=true
  - --accesslog.format=json
  - --accesslog.filters.statuscodes=400-599   # noise reduction
  - --accesslog.filters.minduration=100ms     # drop fast requests
```

Ref: [Traefik v3 access logs](https://doc.traefik.io/traefik/reference/install-configuration/observability/logs-and-accesslogs/).

### 3.4 Multi-service override with YAML anchors — S

Update `docs/integrating-a-project.md` pitfall #4 with an idiom that
shares the common labels. Important caveat: docker-compose `labels:`
lists can't use YAML merge-maps (`<<:`); the clean pattern is a
`&anchor` on a sequence + `- *anchor` splat per service. Hand-write the
per-router labels (`rule=`, `services.X.port`); share the enable + network
labels via anchor.

### 3.5 Middlewares cheatsheet — S

New file `docs/middlewares.md` with copy-paste label blocks for:
CORS (note: no wildcards in v3 `accessControlAllowOriginList` — exact
match), compress, per-service BasicAuth, retry. Rate-limit and
circuit-breaker go in a parking lot — useful snippets but hide bugs
locally.

### 3.6 mkcert wildcard HTTPS — M

Only when you actually need secure-context browser APIs (service
workers, `crypto.subtle`, WebAuthn, clipboard).

Setup summary:
1. `mkcert -install` **in PowerShell on Windows** first (for Windows
   browser trust).
2. Share `CAROOT` via `WSLENV=CAROOT/up` into WSL.
3. `mkcert -install` inside WSL (for `curl`, `wget` trust).
4. `mkcert -cert-file localhost.pem -key-file localhost-key.pem localhost "*.localhost"`.
5. New `dynamic/tls.yml` mounted read-only into Traefik as file provider.
6. Add `websecure` entrypoint on `:443`, HTTP→HTTPS redirect, `--providers.file.watch=true`.

Firefox on Windows needs `certutil.exe` (NSS) present when
`mkcert -install` runs. Refs:
[mkcert](https://github.com/FiloSottile/mkcert),
[mkcert issue #357 — WSL install](https://github.com/FiloSottile/mkcert/issues/357),
[DEV 2025 mkcert guide](https://dev.to/_d7eb1c1703182e3ce1782/how-to-set-up-a-local-https-development-environment-in-2025-mkcert-guide-1h8c).

### Parking lot (likely reject)

- traefik-forward-auth / Authentik for dashboard — overkill for single-user.
- Prometheus + Grafana sidecar — weight-to-value negative on a laptop.
- ACME on `.localhost` — impossible; reserved TLD, no public CA will issue.
- Plugin catalog — one more dep to audit.
- File provider for fully declarative routers — second source of truth; label-only is cleaner for <5 projects.

### v3 gotchas to not step on

- `IPWhiteList` renamed to `IPAllowList` in v3.
- Docker labels *are* hot-reloaded by Traefik, but `docker compose` does
  not re-push labels onto a running container — consumer must
  `docker compose up -d` after changing labels. Compose detects the
  diff and recreates just that service.
- Compose `labels:` list vs map form — hub uses list form (required for
  anchor splats). Don't mix in overrides.
- `--providers.file.watch=true` is required if you want cert changes
  picked up without `make restart`.
- Router rules using `Host(\`x.localhost\`)` are v2/v3 compatible; no
  syntax migration needed.

---

## Suggested rollout order

1. **Add auto-hostname `defaultRule`** to `docker-compose.yml` — 2 min.
2. **Access logs to stdout** — 5 min.
3. **Dashboard BasicAuth** (drop `--api.insecure`) — 15 min.
4. **Anchors in multi-service docs** — 20 min.
5. **New `docs/middlewares.md`** — 30 min.
6. **mkcert HTTPS** — 1–2 h, only when needed.
