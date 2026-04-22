# Integrating a project with the local Traefik hub

This guide walks through wiring any dockerized project into the hub so it is
reachable at `<app>.localhost` when the hub is running and at
`localhost:<port>` when it isn't. A runnable reference lives in
[`../examples/whoami/`](../examples/whoami/).

## Prerequisites

- The hub is set up: `make network && make up` in this repo.
- Your project has a `docker-compose.yml` that publishes the service port
  (e.g. `ports: ["3000:3000"]`) — this is what the fallback mode uses.

## Steps

### 1. Copy the two snippet files into your project

```bash
cp /home/domas/traefik/snippets/traefik.mk \
   /home/domas/traefik/snippets/docker-compose.traefik.yml \
   your-project/
```

### 2. Edit `docker-compose.traefik.yml`

Open the override and rename the service key `app:` to match the service in
your base compose file. For example, if your base file has `web:`, change it
to `web:`.

The hub's Docker provider is configured with
`--providers.docker.defaultRule=Host(`{{ normalize .Name }}.localhost`)`, so
any container with `traefik.enable=true` on the `proxy` network is
automatically reachable at `<container-name>.localhost`. The override only
needs three labels:

- `traefik.enable=true`
- `traefik.docker.network=proxy`
- `traefik.http.services.${APP_NAME}.loadbalancer.server.port=${APP_PORT}`
  (Traefik can't guess the upstream port when a container exposes several.)

No explicit router `rule=` is required. If you want a hostname different
from the container name (custom domain, extra aliases), uncomment the
`routers.${APP_NAME}.rule=Host(...)` line in the template. You do **not**
need an `entrypoints` label — routers without one attach to all
entrypoints, and the hub's entrypoint-level redirect handles HTTP→HTTPS.

### 3. Wire `traefik.mk` into your Makefile

At the top of your project's `Makefile`:

```makefile
APP_NAME      ?= myapp        # router/service name in Traefik
APP_PORT      ?= 3000         # in-container port your service listens on
# APP_HOST      ?= myapp.localhost   # optional; defaults to <dir-name>.localhost
# APP_HOST_PORT ?= 3000              # optional; host-published port for fallback URL.
#                                      defaults to APP_PORT. Set if ports: maps
#                                      host:container differently, e.g. "8081:80".

include traefik.mk

.PHONY: up down logs
up:   ; $(COMPOSE) up -d && $(MAKE) traefik-info
down: ; $(COMPOSE) down
logs: ; $(COMPOSE) logs -f
```

`traefik.mk` defines `COMPOSE` with the correct `-f` flags based on whether
the hub is running.

### 4. Run it

```bash
make up
make traefik-info
```

You should see either:

```
Traefik: running
Mode:    routed via Traefik
Access:  https://myapp.localhost
```

...or the fallback variant with `http://localhost:3000`.

## Mental model

There is **one** base compose file in your project, Traefik-unaware. The
override only gets layered on when the hub is up. That means:

- You can develop with the hub off and your project still works normally.
- Turning the hub on/off requires re-running `make up` in the project
  (compose applies overrides at up-time, not runtime).
- The base compose should keep its `ports:` block so fallback mode actually
  publishes the service. The override doesn't need to remove it — Traefik
  will route through the internal network regardless, and a published host
  port doesn't hurt.

## HTTPS in routed mode

When the hub is up, consumer routers are served at
`https://<app>.localhost` with a locally-trusted mkcert cert. HTTP is
redirected to HTTPS at the hub's entrypoint, so consumers do **not**
need `tls=true` or `entrypoints=websecure` labels — a router with no
explicit `entrypoints` label attaches to all entrypoints, and the
entrypoint-level redirect takes care of the rest. No cert generation in
the consumer repo either: the hub's wildcard cert covers `*.localhost`.
When the hub is down, fallback mode serves plain HTTP on
`localhost:<APP_HOST_PORT>` exactly as before. One-time cert setup lives
in [`https.md`](https.md).

## Multiple services in one project

The single-service template assumes one router/service per compose project.
For a project with several web-facing services, skip `traefik.mk`'s
`APP_NAME` plumbing for the override and write it by hand.

To share common labels across services, use compose's **map-form** `labels:`
block together with a YAML merge-key (`<<:`). The sequence form (`labels: -
key=value`) does not merge cleanly because splatting an anchored sequence
into a sequence produces a nested list, which compose rejects with
`unexpected type []interface {}`. Map form avoids the whole problem:

```yaml
# docker-compose.traefik.yml
x-traefik-common: &traefik-common
  traefik.enable: "true"
  traefik.docker.network: proxy

services:
  web:
    labels:
      <<: *traefik-common
      traefik.http.services.web.loadbalancer.server.port: "3000"
    networks: [proxy, default]

  api:
    labels:
      <<: *traefik-common
      traefik.http.services.api.loadbalancer.server.port: "8080"
      # Override the auto hostname (defaults to <container-name>.localhost):
      traefik.http.routers.api.rule: "Host(`api.myproject.localhost`)"
    networks: [proxy, default]

  pgadmin:
    labels:
      <<: *traefik-common
      traefik.http.services.pgadmin.loadbalancer.server.port: "80"
    networks: [proxy, default]

networks:
  proxy:
    external: true
```

Each service keeps its per-router and per-service labels explicit; only the
enable + network labels are shared via `<<: *traefik-common`. Quote numeric
and boolean values (`"true"`, `"3000"`) — YAML would otherwise convert them,
and Traefik labels are strings. Router names must be unique per project.

## Pitfalls

- **Service name mismatch.** If you forget to rename `app:` in the override,
  compose merges it as a new service and your real service gets no labels.
  `docker compose config` will show the truth.
- **`APP_PORT` is the in-container port.** That is the port Traefik uses as
  the upstream target, and it matches what your service binds to inside the
  container. If your base compose publishes a different host port
  (`ports: ["8081:80"]`), set `APP_HOST_PORT=8081` so the fallback URL
  points at the right port.
- **Missing `proxy` network.** Run `make network` in the hub repo once per
  machine, or add `docker network create proxy` to your own bootstrap.
