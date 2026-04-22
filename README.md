# Local Traefik Dev Hub

A tiny, shared Traefik v3 reverse proxy for local development. One container,
one `proxy` network, and a drop-in Makefile snippet that lets any dockerized
project auto-route at `<app>.localhost` when the hub is up and transparently
fall back to `localhost:<port>` when it isn't.

## Why

Juggling local ports across many projects gets old. With the hub running:

- `myapi.localhost`, `web.localhost`, `db-admin.localhost`, ... instead of
  `:3000`, `:3001`, `:5050`.
- Consumer projects need zero Traefik knowledge in their base compose file.
- Turn the hub off and everything still works via plain ports — same
  containers, same compose.

## Quickstart

```bash
make network      # create the shared 'proxy' docker network
make up           # start Traefik
open http://traefik.localhost
```

Other targets: `make down`, `make logs`, `make status`, `make restart`.

## Adding a project to the hub

See [`docs/integrating-a-project.md`](docs/integrating-a-project.md) for the
step-by-step. Short version:

1. Copy `snippets/traefik.mk` and `snippets/docker-compose.traefik.yml` into
   the consumer repo.
2. Set `APP_NAME` and `APP_PORT` in the consumer Makefile and
   `include traefik.mk`.
3. Run `make up` in the consumer project.

A working reference lives in [`examples/whoami/`](examples/whoami/).

## Mental model

```
                       hub up                        hub down
consumer `make up`  →  routed via Traefik         →  published on host ports
                       http://<app>.localhost        http://localhost:<port>
```

Flipping hub state requires re-running `make up` in the consumer (the compose
override is evaluated at up-time, not runtime).

## Troubleshooting

- **Port 80 already allocated** — another local proxy or web server is bound
  to `:80`. Stop it or change the hub's `--entrypoints.web.address` and its
  host port mapping.
- **`Error response from daemon: network proxy not found`** — run
  `make network` first, or `docker network create proxy`.
- **Container up but `*.localhost` 404s** — check labels with
  `docker inspect <container> | grep traefik` and confirm the container is on
  the `proxy` network (`make status`).
- **Dashboard is open to the world** — the hub uses `--api.insecure=true`
  which is fine on a dev laptop but never on a shared or public host.

## Scope

This repo is deliberately small: HTTP only, local-only, no auth, no
middleware chains. See the approved plan in the project history if you want
to extend it (HTTPS via mkcert was explicitly deferred).
