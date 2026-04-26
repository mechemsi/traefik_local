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
- HTTP-only by design. Local trust-store dance with mkcert is too much
  friction for the value; consumer routers serve plain HTTP at
  `http://<app>.localhost`. Browser secure-context features (service
  workers, WebCrypto, etc.) are unavailable as a result — if you need
  them, add HTTPS back yourself.

## Quickstart

### First-time setup: dashboard password

The dashboard at `traefik.localhost` is protected by BasicAuth. Before the
first `make up`, put a bcrypt hash in `.env`.

```bash
# On Debian/Ubuntu/WSL, htpasswd comes from apache2-utils:
sudo apt install apache2-utils

cp .env.example .env
htpasswd -nB admin            # copy the output
$EDITOR .env                  # paste it into DASHBOARD_AUTH, doubling every $
```

Example: an `htpasswd` output of `admin:$2y$05$abc...` becomes
`DASHBOARD_AUTH=admin:$$2y$$05$$abc...` in `.env`. The doubling is
required because docker compose runs variable interpolation on
`.env` values — a bare `$2y` would be read as an unset variable and
silently dropped. `.env` is gitignored, so your hash never enters git.

`make up` will fail fast with a helpful message if `DASHBOARD_AUTH`
isn't set.

### Bring it up

```bash
make network      # create the shared 'proxy' docker network
make up           # start Traefik
open http://traefik.localhost
```

Other targets: `make down`, `make logs`, `make status`, `make restart`.

## Adding a project to the hub

See [`docs/integrating-a-project.md`](docs/integrating-a-project.md) for the
step-by-step. Quickest path — from this repo:

```bash
make install TARGET=../your-project APP_NAME=myapi APP_PORT=8080
```

That copies the snippets in, wires up the consumer Makefile, and prints
the URLs. Then rename the `app:` service in the generated
`docker-compose.traefik.yml` to match your real service, and run
`make up` in the consumer project.

Manual three-step alternative:

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
- **Browser sends `https://`** — Chrome/Edge cache HSTS for hosts they
  previously served over HTTPS. If you used the hub's earlier HTTPS
  setup, clear HSTS for the affected `.localhost` hosts at
  `chrome://net-internals/#hsts` ("Delete domain security policies").

## Claude Code skills

Two skills ship with the hub for teams using Claude Code. Both live in
[`skills/`](skills/) and are version-controlled with the snippets they
describe.

- `traefik-integrate-project` — operator-mode wire-up of a consumer
  project. Auto-invoked when a developer asks to route a project at
  `<name>.localhost`, add an app to the local Traefik, etc. Detects
  service name + ports, runs `install.sh`, patches the override,
  verifies the route.
- `traefik-hub-maintain` — common edits + diagnostics inside the hub
  repo (add CORS / basicauth / compress middleware, reset dashboard
  auth, triage routed-but-404 containers).

Install once per machine:

```bash
make install-skills
```

This symlinks each skill into `~/.claude/skills/`, so `git pull` of
this repo flows updates through automatically. Restart Claude Code
once after installing for it to pick them up. `make uninstall-skills`
reverses it.

## Scope

This repo is deliberately small: local-only, HTTP-only, minimal
middleware chains. No HTTPS by design — the trust-store setup for
local TLS is more friction than it's worth for a dev hub. No auth on
consumer routers by default. Everything stays local-only.
