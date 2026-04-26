---
name: traefik-hub-maintain
description: Use when working inside a local Traefik hub repository (the one shipping snippets/traefik.mk and a top-level docker-compose.yml with a traefik: service) and the developer asks to add a middleware (CORS, basicauth, retry, compress) to a routed consumer, regenerate local certs, fix dashboard auth, debug a routed-but-404 container, troubleshoot the proxy network, or extend the hub's docs/snippets. Also use for v3 label-syntax questions like IPAllowList vs IPWhiteList or `$$` doubling in compose label values.
---

# Maintain the local Traefik hub

## Overview

Hub-side companion to `traefik-integrate-project`. Covers two flows:

1. **Common edits** — adding middleware to a consumer, regenerating
   certs, resetting dashboard auth, lint-after-edit.
2. **Diagnostics** — triaging a routed-but-404 container, cert-not-trusted
   reports, label-syntax bugs.

Out of scope: structural rewrites of the hub (new entrypoints, new
providers, swapping the `defaultRule`). Those are repo-shaped decisions
that should go through brainstorming + a PR review, not a skill.

**REQUIRED BACKGROUND:** Read `_shared/SNIPPET-CONTRACT.md` in this
skill's parent directory. The diagnostics flows assume you understand
the hub-up/hub-down toggle, the `proxy` network requirement, the
container-name trap, and v3 label gotchas.

## When to use

Triggers (any of):
- Working in a directory containing `docker-compose.yml` with a
  `traefik:` service AND `snippets/traefik.mk` AND
  `dynamic/`. (Distinguishes the hub from a consumer.)
- "add a CORS middleware to <consumer>"
- "put basicauth in front of <service>"
- "add compression / retry to <route>"
- "regenerate the local certs" / "the cert is expired"
- "the dashboard wants a password I don't know"
- "this container is up but I get 404 at `<name>.localhost`"
- "Traefik isn't picking up my labels"
- v3 label-syntax questions (`IPWhiteList`, `$$` doubling, etc.)

When NOT to use:
- Wiring a new project into the hub → `traefik-integrate-project`.
- Production Traefik. This skill assumes the local mkcert-based hub.

## Pre-flight (every flow)

Run these once at the top of any session in the hub repo. Cheap and
catches most "why isn't this working" before it gets weird:

```bash
# In hub repo
make status                # hub running? what's labeled?
[ -f .env ] && grep -q DASHBOARD_AUTH .env || echo "WARN: .env missing DASHBOARD_AUTH"
[ -f certs/localhost.pem ] && [ -f certs/localhost-key.pem ] || echo "WARN: certs missing — make certs"
docker network inspect proxy >/dev/null 2>&1 || echo "WARN: proxy network missing — make network"
```

Pre-flight findings shape the next move. Don't skip.

## Common-edits flow

### Add a middleware to a consumer

Middlewares declared on **any** container register with the `@docker`
provider. Attach them to a router by adding them to that router's
`middlewares=` label. Order matters: middlewares run left-to-right on
the request, right-to-left on the response.

Add to the consumer's `docker-compose.traefik.yml`, not the hub itself.
Recipe — CORS for an API hit from a separately-hosted local frontend:

```yaml
labels:
  - traefik.http.routers.api.middlewares=api-cors@docker
  - traefik.http.middlewares.api-cors.headers.accessControlAllowMethods=GET,POST,PUT,DELETE,OPTIONS
  - traefik.http.middlewares.api-cors.headers.accessControlAllowHeaders=Content-Type,Authorization
  - traefik.http.middlewares.api-cors.headers.accessControlAllowOriginList=https://web.localhost,https://app.localhost
  - traefik.http.middlewares.api-cors.headers.accessControlAllowCredentials=true
  - traefik.http.middlewares.api-cors.headers.addVaryHeader=true
```

`accessControlAllowOriginList` takes **exact origin matches only** —
no `*`, no wildcards. If the developer needs patterns, use
`accessControlAllowOriginListRegex`. See `docs/middlewares.md` for the
catalogue (CORS, compress, basicauth, retry).

After editing labels: `docker compose up -d` in the consumer (compose
doesn't push label changes to running containers; Traefik's hot-reload
only fires on Docker events, which compose triggers by recreating).

### Add basicauth in front of a service

```yaml
labels:
  - traefik.http.routers.<svc>.middlewares=<svc>-auth@docker
  - traefik.http.middlewares.<svc>-auth.basicauth.users=<user>:<bcrypt-hash-with-doubled-$>
```

Generate the hash + double `$` in one shot:

```bash
htpasswd -nB <user> | sed -e 's/\$/\$\$/g'
```

Compose runs variable interpolation on label values. A bare `$2y$05$...`
is read as the unset variable `$2y` and silently dropped. Doubling is
mandatory.

The hub terminates TLS, so basicauth credentials are encrypted in
transit even on local dev — no plaintext passwords on the wire.

### Regenerate certs

```bash
make certs   # mkcert-based; refuses to run if mkcert missing
```

If `mkcert` isn't installed, the target prints install instructions
and exits non-zero. Don't try to install mkcert from the skill — it
modifies the system trust store and (on WSL) needs to be installed in
both Windows and WSL. Point the developer at `docs/https.md` for the
one-time setup.

After regeneration: `make restart` to pick up the new cert. Browsers
may need a restart to clear cached cert state.

### Reset dashboard auth

`.env` holds `DASHBOARD_AUTH=<user>:<bcrypt-with-doubled-$>`. Generate:

```bash
htpasswd -nB admin                    # copy output
# Edit .env, paste into DASHBOARD_AUTH, then double every $:
sed -i 's/\$/\$\$/g' .env             # only if .env contains the raw hash
make restart
```

The `$$` doubling is the same compose-interpolation rule as label
values. `.env` is gitignored — the hash never enters git.

### After any hub or snippet edit

```bash
make lint     # validates hub compose + example consumer compose
```

`make lint` parses both compose files via `docker compose config
--quiet` and exits non-zero if either fails. It does NOT lint the
snippet files in isolation — those need a real consumer to apply
against. The whoami example fills that role.

## Diagnostics flow

### Routed-but-404 (container up, `<name>.localhost` returns 404)

Order of investigation (cheapest to most invasive):

1. **Hostname matches container name?** `defaultRule` keys off the
   container name as Docker reports it. Compose v2 names containers
   `<project>-<service>-N`. Check:
   ```bash
   docker ps --format '{{.Names}}'
   ```
   If the developer expects `myapp.localhost` but the container is
   `myproject-myapp-1`, they need either an explicit `Host()` rule on
   the router or `container_name:` set on the base service. See
   `_shared/SNIPPET-CONTRACT.md` "container-name trap".

2. **Container on the proxy network?**
   ```bash
   docker inspect <container> --format '{{json .NetworkSettings.Networks}}' | jq
   ```
   Must include `proxy`. If missing, the override didn't get applied
   (forgot to bring it up with `-f docker-compose.traefik.yml`?) or the
   service wasn't renamed in the override.

3. **Labels on the container?**
   ```bash
   docker inspect <container> --format '{{json .Config.Labels}}' | jq | grep traefik
   ```
   Must include `traefik.enable=true` and a service `loadbalancer.server.port`.
   No labels = override didn't apply to this service. Confirm with:
   ```bash
   cd <consumer>
   docker compose -f docker-compose.yml -f docker-compose.traefik.yml config | grep -A20 "<service>:"
   ```
   Look for the labels in the merged output. Their absence almost
   always means the override's service key (`app:` in the template)
   wasn't renamed to match the base compose.

4. **Traefik sees the router?** Check the dashboard at
   `https://traefik.localhost` (HTTP Routers). If the router is
   listed, the labels are valid; the issue is upstream (port wrong,
   service down, network unreachable from Traefik). If the router is
   missing, Traefik rejected the labels — check `make logs` for parse
   errors.

5. **Upstream port wrong?** Most common cause of 502 (not 404), but
   worth checking if 4 looks fine. `loadbalancer.server.port` must be
   the **in-container** port the service listens on, not the
   host-published port from `ports:`.

### Cert-not-trusted

Almost always one of:

- mkcert's CA not installed in the browser's trust store. Run
  `mkcert -install` once per machine. On WSL, also install in Windows
  (mkcert's CA needs to live in both — `docs/https.md` covers this).
- Firefox: uses its own trust store. `mkcert -install` handles it but
  Firefox needs a restart.
- Cert expired. Regenerate with `make certs` and `make restart`.

### Labels look right but Traefik ignores them

Two known causes:

1. **Edited labels on a running container.** Compose doesn't push label
   updates. Run `docker compose up -d` to recreate the service.
2. **Used a v2 middleware name.** `IPWhiteList` was renamed to
   `IPAllowList` in v3. Old internet examples use the v2 name and
   silently fail to register. Other v2→v3 renames exist; cross-check
   the [Traefik v3 docs](https://doc.traefik.io/traefik/middlewares/http/overview/)
   if the middleware name is from a Stack Overflow answer dated before
   2024.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forgot to double `$` in label / .env value | basicauth always fails / dashboard locks out | `sed 's/\$/\$\$/g'` the value, restart. |
| Edited labels expecting hot-reload | Old behavior persists | `docker compose up -d` to recreate. |
| Used `*` in `accessControlAllowOriginList` | CORS preflight fails | List exact origins, or use `…OriginListRegex`. |
| Ran `mkcert -install` only in WSL on Windows host | Browser shows "not trusted" | Install mkcert + run `mkcert -install` in both Windows and WSL. |
| Made a structural change to the hub via this skill | Out-of-scope churn | Stop. Discuss the design first; this skill is for common edits + diagnostics only. |
| Skipped pre-flight, debugged a stopped hub | "Why is nothing routing?" | `make status` first, every session. |

## Quick reference

| Task | Command |
|---|---|
| Pre-flight | `make status && ls certs/ && docker network inspect proxy` |
| Lint after edits | `make lint` |
| Restart after cert/auth change | `make restart` |
| Inspect container labels | `docker inspect <c> --format '{{json .Config.Labels}}' \| jq` |
| Inspect container networks | `docker inspect <c> --format '{{json .NetworkSettings.Networks}}' \| jq` |
| See merged consumer compose | `docker compose -f docker-compose.yml -f docker-compose.traefik.yml config` |
| Tail Traefik logs | `make logs` |
| Generate basicauth value | `htpasswd -nB <user> \| sed -e 's/\$/\$\$/g'` |
