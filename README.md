# Local Traefik Dev Hub

A tiny, shared Traefik v3 reverse proxy for local development. One container,
one `proxy` network, and a drop-in Makefile snippet that lets any dockerized
project auto-route at `<app>.localhost` when the hub is up and transparently
fall back to `localhost:<port>` when it isn't.

## Why

Juggling local ports across many projects gets old. With the hub running:

- `myapi.localhost`, `web.localhost`, `db-admin.localhost`, ... instead of
  `:3000`, `:3001`, `:5050`.
- `<container-name>.localhost` is assigned automatically to every labeled
  container via Traefik's `defaultRule` — no explicit `Host()` rule needed
  unless you want a non-default name.
- Consumer projects need zero Traefik knowledge in their base compose file.
- Turn the hub off and everything still works via plain ports — same
  containers, same compose.
- The `.localhost` TLD resolves to loopback automatically in modern
  browsers (Chrome, Firefox, Edge) per RFC 6761 — no `/etc/hosts` edits.
  On Windows 11, make sure the host is patched past the Nov 2025
  cumulative rollup to avoid the KB5066835 loopback HTTP/2 regression.

## Quickstart

### First-time setup: dashboard password

The dashboard at `traefik.localhost` is protected by BasicAuth. Before the
first `make up`, generate a bcrypt hash for the `admin` user and paste it
into `docker-compose.yml`.

```bash
# On Debian/Ubuntu/WSL, htpasswd comes from apache2-utils:
sudo apt install apache2-utils

htpasswd -nB admin
# Example output:
#   admin:$2y$05$Abc...xyz
```

In `docker-compose.yml`, find the line:

```
- traefik.http.middlewares.dashboard-auth.basicauth.users=admin:$$2y$$05$$PLACEHOLDER_REPLACE_ME
```

Paste your hash in place of the placeholder, **doubling every `$`**.
docker-compose uses `$` for variable expansion, so an htpasswd output of
`$2y$05$abc...` must be written as `$$2y$$05$$abc...`. Leave the
`admin:` prefix as-is.

### Bring it up

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

## Scope

This repo is deliberately small: HTTP only, local-only, no auth, no
middleware chains. See the approved plan in the project history if you want
to extend it (HTTPS via mkcert was explicitly deferred).
