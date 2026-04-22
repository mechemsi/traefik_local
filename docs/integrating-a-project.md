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
to `web:`. Everything else can stay as-is — the labels use `${APP_NAME}` /
`${APP_HOST}` / `${APP_PORT}` which are provided by `traefik.mk`.

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
Access:  http://myapp.localhost
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
- **Multiple services.** Repeat the labels block once per service in the
  override, each with a unique `APP_NAME`-derived router name. For
  multi-service projects it is often cleanest to write the override by hand
  rather than reusing the single-service template verbatim.
