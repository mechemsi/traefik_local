# Hub snippet contract

Reference shared by `traefik-integrate-project` and `traefik-hub-maintain`.
What the three snippet files do, what variables they consume, and the
gotchas that don't show up in `docs/integrating-a-project.md`.

## The three snippets

`snippets/traefik.mk` — Makefile include for the consumer project.

- Detects `docker inspect -f '{{.State.Running}}' traefik` at evaluation time.
- Hub running → `COMPOSE := docker compose -f docker-compose.yml -f docker-compose.traefik.yml`
- Hub down  → `COMPOSE := docker compose -f docker-compose.yml -f docker-compose.fallback.yml`
- Exports `APP_NAME`, `APP_HOST`, `APP_PORT`, `APP_HOST_PORT` so both
  overlay files can interpolate them.
- `traefik-info` target prints current mode + access URL.

`snippets/docker-compose.traefik.yml` — overlay applied only when the hub
is up. Three labels + a network attach:

- `traefik.enable=true`
- `traefik.docker.network=proxy`
- `traefik.http.services.${APP_NAME}.loadbalancer.server.port=${APP_PORT}`

Adds no `ports:` — Traefik reaches the container over the internal
`proxy` network, so nothing is published to the host in routed mode.

The hub-side Docker provider runs with
`--providers.docker.defaultRule=Host(`{{ normalize .Name }}.localhost`)`,
so a labeled container theoretically auto-routes at
`<container-name>.localhost` without an explicit router rule.

`snippets/docker-compose.fallback.yml` — overlay applied only when the hub
is down. One concern: publish the in-container port on the host so the
service is reachable at `http://localhost:${APP_HOST_PORT}`.

```yaml
services:
  app:
    ports:
      - "${APP_HOST_PORT}:${APP_PORT}"
```

Same `app:` → real-service-name rename gotcha as the routed overlay (see
"The container-name trap" below — same root cause: forgetting to rename
silently creates a phantom `app:` service and your real service stays
unpublished).

## Variables

| Var | Default | Meaning |
|---|---|---|
| `APP_NAME` | `$(notdir $(CURDIR))` (directory name) | Router/service name in Traefik labels. **Not** the compose service name. |
| `APP_HOST` | `$(APP_NAME).localhost` | Hostname Traefik routes to in routed mode. |
| `APP_PORT` | `3000` | **In-container** port the service listens on. The Traefik upstream target. |
| `APP_HOST_PORT` | `$(APP_PORT)` | **Host-published** port for the fallback overlay (`ports: ["${APP_HOST_PORT}:${APP_PORT}"]`). Set explicitly only when host:container should differ — e.g. avoiding a collision on `:80`, set `APP_HOST_PORT=8081`. |

## The container-name trap (critical)

`defaultRule` keys off the container name as Docker reports it. With
modern compose (v2), `docker compose up` names containers
`<project>-<service>-N` unless `container_name:` is set. So a base
compose with service `web:` in directory `myapp/` produces a container
named `myapp-web-1` — and `defaultRule` routes it at
`myapp-web-1.localhost`, **not** `myapp.localhost` or `web.localhost`.

The hub's `examples/whoami/` happens to set `container_name: whoami`, so
its docs work as written. Most real consumer projects don't.

**Two fixes; pick one per project:**

1. **Explicit `Host()` rule in the override** (recommended default — keeps
   the base compose Traefik-unaware):
   ```yaml
   - traefik.http.routers.${APP_NAME}.rule=Host(`${APP_HOST}`)
   ```
2. **Set `container_name:`** on the service in the base compose. Cleaner
   labels (no `rule=` needed) but mixes routing concerns into the base
   file. Only do this if the consumer is OK with a fixed container name.

## Ports policy (where `ports:` lives)

The base `docker-compose.yml` for a Traefik-integrated consumer must
**not** declare `ports:` for the web-facing service. Compose merges the
`ports:` key additively (override entries are *appended* to the base
list, not replaced), so a base-level `ports:` block would publish in
both routed and fallback modes — re-introducing the host-port-collision
problem the routed/fallback split exists to avoid.

The split:

- Routed mode (hub up) → `docker-compose.traefik.yml` adds labels +
  proxy network, **no `ports:`**. Traefik reaches the container over
  the internal network.
- Fallback mode (hub down) → `docker-compose.fallback.yml` adds
  `ports: ["${APP_HOST_PORT}:${APP_PORT}"]`. Nothing else.

If a developer runs `docker compose up` directly (bypassing `make`),
neither overlay applies and the container won't be reachable from the
host. That's expected — `make` is the supported entrypoint. Tools that
need the published port (devcontainer, IDE attach) should be wired
through the Makefile workflow, or use `docker compose -f
docker-compose.yml -f docker-compose.fallback.yml up`.

## Hub-up vs hub-down toggle

The toggle is evaluated **at `make` invocation time**, not container
runtime. Flipping the hub on or off does not re-route already-running
consumer containers. The consumer must re-run `make up` to pick up the
new overlay set. This is intentional: compose merges overrides at
up-time.

## The proxy network

`docker-compose.traefik.yml` declares the `proxy` network as
`external: true`. If the network doesn't exist, compose errors out at
up-time with `network proxy not found`. Bootstrap once per machine via
`make network` in the hub repo, or `docker network create proxy`.

In fallback mode (hub down), the routed overlay isn't loaded, so the
missing network doesn't block startup — only routed mode is affected.

## v3 label syntax (compose-side gotchas)

- `$` in label values must be doubled. Compose runs variable expansion
  on label values, so `$2y$05$...` in a basicauth hash becomes
  `$$2y$$05$$...`. One-liner: `htpasswd -nB user | sed -e 's/\$/\$\$/g'`.
- `IPWhiteList` was renamed to `IPAllowList` in Traefik v3. Old examples
  on the internet still use the v2 name and silently fail to register.
- Label changes on a running container are not picked up by Traefik
  hot-reload — Docker doesn't push updated labels to running containers.
  Run `docker compose up -d` after editing labels; compose detects the
  diff and recreates just that service.

## CORS specifics

`accessControlAllowOriginList` accepts **exact origin matches only** — no
`*`, no wildcards. List every origin explicitly. Use
`accessControlAllowOriginListRegex` for patterns.

## Multi-service consumers

`traefik.mk`'s single `APP_NAME`/`APP_PORT` plumbing assumes one
web-facing service per compose project. For multi-service projects, skip
the variable plumbing and write the override by hand using compose's
**map-form** `labels:` block with a YAML merge-key:

```yaml
x-traefik-common: &traefik-common
  traefik.enable: "true"
  traefik.docker.network: proxy

services:
  api:
    labels:
      <<: *traefik-common
      traefik.http.services.api.loadbalancer.server.port: "8080"
    networks: [proxy, default]
```

The sequence form (`labels: - key=value`) does not merge cleanly with
YAML anchors — splatting an anchored sequence into a sequence produces a
nested list and compose rejects it with `unexpected type []interface {}`.
Quote numeric and boolean values; Traefik labels are strings.
