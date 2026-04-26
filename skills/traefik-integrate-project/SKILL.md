---
name: traefik-integrate-project
description: Use when a developer asks to wire a dockerized project into a local Traefik reverse-proxy hub, route a service at a friendly *.localhost hostname, add a project to the proxy/Traefik dev hub, or set up Traefik for a docker-compose app. Symptoms include the project having a docker-compose.yml without traefik.mk or docker-compose.traefik.yml, and the developer wanting URLs like https://myapp.localhost instead of localhost:3000.
---

# Wire a project into the local Traefik hub

## Overview

Operator-mode integration: detect the project's compose layout, run the
hub's installer, patch the override to the actual service, verify
preconditions, and bring it up. Designed for the hub at
[github.com/mechemsi/traefik_local](https://github.com/mechemsi/traefik_local).

**REQUIRED BACKGROUND:** Read `_shared/SNIPPET-CONTRACT.md` in this
skill's parent directory before starting. It documents the
container-name trap, the variable contract, and the v3 label gotchas
the workflow below assumes you understand.

## When to use

Triggers (any of):
- "wire this project into Traefik / the hub / the proxy"
- "make this routable at `<name>.localhost`"
- "add this app to the local Traefik"
- Project has a `docker-compose.yml` but no `traefik.mk` and the
  developer wants a friendly hostname.

When NOT to use:
- Production / non-local Traefik. This skill targets a local dev hub
  with mkcert TLS for `*.localhost`.
- Modifying the hub itself (adding middleware, debugging routes,
  regenerating certs) → use `traefik-hub-maintain` instead.

## The workflow

```
1. Pre-flight (locate hub, read base compose, detect values)
2. Confirm plan with developer (one prompt, coarse)
3. Install snippets (run installer)
4. Patch override (rename service, set hostname strategy)
5. Verify preconditions (proxy network, hub state)
6. make up + verify routing
```

### 1. Pre-flight detection

Locate the hub repo. Default `~/traefik`; if absent, ask the developer
for the path. Confirm by checking for `snippets/traefik.mk` and
`snippets/docker-compose.traefik.yml`.

Read the consumer's base `docker-compose.yml`. Extract:

- **Service name** — the top-level key under `services:`. If multiple
  services, ask which one is the web-facing target. (Multi-service is a
  separate flow — see `_shared/SNIPPET-CONTRACT.md` "Multi-service
  consumers" and write the override by hand.)
- **Container port** — what the service listens on inside the
  container. Inferred from the right side of `ports: ["X:Y"]` (Y), the
  service's `EXPOSE` if no `ports:`, or asked if ambiguous. This is
  `APP_PORT`.
- **Host port** — the left side of `ports: ["X:Y"]` (X). This is
  `APP_HOST_PORT`. Set explicitly only when it differs from `APP_PORT`.
- **`container_name:` set?** — determines hostname strategy below.

Compute:

- `APP_NAME` = the project directory's basename (`$(basename $PWD)`).
  **Never** the compose service name unless the developer explicitly
  asks. Service names are often generic (`web`, `app`, `api`); the
  router/service name in Traefik labels should identify the project.
- `APP_HOST` = `${APP_NAME}.localhost`.

### 2. Confirm plan

Print one consolidated plan and ask once before mutating files:

```
About to:
  - run <hub>/scripts/install.sh <pwd> with APP_NAME=<x> APP_PORT=<y>
  - set APP_HOST_PORT=<n> in the Makefile  (only if host port ≠ container port)
  - rename `app:` → `<service>` in docker-compose.traefik.yml
  - set Host() rule on the override (because container_name not set in base)
  - ensure docker network `proxy` exists
  - run `make up` and verify https://<host> responds
Proceed?
```

Don't ask per-step. Coarse confirmation is the design.

Include `APP_HOST_PORT` in the plan whenever step 1 detected a
host-published port that differs from the container port — it's the
variable most likely to be wrong silently in fallback mode.

### 3. Install snippets

Prefer the local clone (idempotent + offline-safe):

```bash
HUB=/path/to/traefik_local
APP_NAME=<name> APP_PORT=<container-port> "$HUB/scripts/install.sh" "$PWD"
```

The installer copies `traefik.mk` + `docker-compose.traefik.yml`,
creates or appends to `Makefile` with the include block, and prompts
before overwriting existing snippet files. It auto-detects local vs
remote source.

If the consumer has an existing `Makefile`, the installer detects an
existing `include traefik.mk` and skips the Makefile change. If
variables (`APP_NAME`, `APP_HOST_PORT`) need to be set, append them
above the `include` line yourself — installer doesn't manage them.

**The installer is intentionally dumb about your service name.** It
copies `docker-compose.traefik.yml` verbatim from the template, with
`app:` as the service key. It does **not** know what your real service
is called and will not rename it. That's step 4 below — your job, not
the installer's.

### 4. Patch the override

The installer copies the template with `app:` as the service key. Edit
`docker-compose.traefik.yml`:

1. **Rename `app:` → actual service name** from the base compose. This
   is the #1 silent failure: if you forget, compose merges `app:` as a
   new (label-less) service and your real service stays unrouted.
   Verify after with `docker compose config` — the merged output should
   show your service with all the Traefik labels attached.
2. **Hostname strategy** (see `_shared/SNIPPET-CONTRACT.md` for the
   full container-name trap):
   - If `container_name:` is set on the base service AND matches
     `APP_NAME`: leave the override as shipped, defaultRule will
     produce `${APP_NAME}.localhost`.
   - Otherwise (typical case with compose v2): uncomment the explicit
     rule line:
     ```yaml
     - traefik.http.routers.${APP_NAME}.rule=Host(`${APP_HOST}`)
     ```
3. Set `APP_HOST_PORT` in the consumer Makefile if it differs from
   `APP_PORT`. Otherwise omit — defaults to `APP_PORT`.

### 5. Verify preconditions

```bash
# Proxy network exists?
docker network inspect proxy >/dev/null 2>&1 \
  || (cd "$HUB" && make network)

# Hub running? (Determines URL the developer should hit, but isn't
# required for `make up` to succeed — fallback mode works hub-down.)
docker inspect -f '{{.State.Running}}' traefik 2>/dev/null
```

If the hub is stopped and the developer wants routed mode, point them
at `cd "$HUB" && make up` (which itself requires `make certs` first if
they've never run it). Don't run `make up` in the hub repo without
asking — it's their hub.

### 6. Bring it up + verify

```bash
make up
make traefik-info  # if defined; otherwise check `make up` output
```

Expected `traefik-info` output in routed mode:
```
Traefik: running
Mode:    routed via Traefik
Access:  https://<APP_HOST>
```

Verify routing reaches the app:
```bash
curl -k -sS -o /dev/null -w '%{http_code}\n' https://${APP_HOST}
# 200 = working. 404 = labels didn't take (most likely service-name
# mismatch in the override — re-check step 4.1).
```

`-k` is required because mkcert's CA might not be trusted by curl even
when browsers trust it.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forgot to rename `app:` in override | 404 at `https://<host>` after `make up` | `docker compose config` shows two services, only one labeled. Edit override. |
| `APP_PORT` set to host port | 502 Bad Gateway from Traefik | `APP_PORT` is the **in-container** port. Swap to the right side of `ports: ["X:Y"]`. |
| `APP_NAME` = compose service name (`web`, `app`) | Router collisions across projects | Use directory basename. Multiple consumers all routing `app.localhost` is the failure. |
| Used defaultRule without `container_name:` | Routes at `<project>-<service>-1.localhost` | Add the explicit `Host()` rule (preferred) or set `container_name:` on base service. |
| `proxy` network missing | `network proxy not found` at compose up | `make network` in hub repo, or `docker network create proxy`. |
| Hub not running, expected `https://<host>` to work | Connection refused | Fallback mode is `http://localhost:${APP_HOST_PORT}`. Either start the hub or use the fallback URL. |
| Multi-service project, used the single-service template | Some services unrouted, label conflicts | Skip `traefik.mk`'s `APP_NAME` plumbing. Hand-write the override using map-form labels + YAML merge-keys (see `_shared/SNIPPET-CONTRACT.md`). |
| Edited labels on running container, expected hot-reload | Old routing persists | Compose doesn't push label updates. Run `docker compose up -d` to recreate the service. |

## Quick reference

| Step | Command |
|---|---|
| Detect base compose | `cat docker-compose.yml` then read services + ports |
| Install | `APP_NAME=<x> APP_PORT=<y> "$HUB/scripts/install.sh" "$PWD"` |
| Verify merge | `docker compose -f docker-compose.yml -f docker-compose.traefik.yml config` |
| Bring up | `make up && make traefik-info` |
| Verify routing | `curl -k https://${APP_HOST}` |
| Network bootstrap | `cd "$HUB" && make network` |
