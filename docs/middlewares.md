# Middlewares cheatsheet

Copy-paste Traefik v3 middleware snippets for the local hub. Middlewares
are defined and attached via Docker labels, usually in the consumer
project's `docker-compose.traefik.yml` override.

A middleware declared on any container is registered in the `@docker`
provider. Attach it to a router with
`traefik.http.routers.<router>.middlewares=<mw1>@docker,<mw2>@docker`.
Order matters: middlewares run left-to-right on the request, right-to-left
on the response.

See the [Traefik v3 middleware reference](https://doc.traefik.io/traefik/middlewares/http/overview/)
for the full catalogue.

## CORS (dev-friendly)

Permissive CORS for a local API being hit from a separately-hosted
frontend:

```yaml
labels:
  - traefik.http.routers.api.middlewares=api-cors@docker
  - traefik.http.middlewares.api-cors.headers.accessControlAllowMethods=GET,POST,PUT,DELETE,OPTIONS
  - traefik.http.middlewares.api-cors.headers.accessControlAllowHeaders=Content-Type,Authorization
  - traefik.http.middlewares.api-cors.headers.accessControlAllowOriginList=http://web.localhost,http://app.localhost
  - traefik.http.middlewares.api-cors.headers.accessControlAllowCredentials=true
  - traefik.http.middlewares.api-cors.headers.accessControlMaxAge=600
  - traefik.http.middlewares.api-cors.headers.addVaryHeader=true
```

Traefik v3 `accessControlAllowOriginList` takes **exact origin matches
only** — no `*`, no wildcards. List every origin explicitly. Use
`accessControlAllowOriginListRegex` if you really need patterns.
[Docs](https://doc.traefik.io/traefik/middlewares/http/headers/#cors-headers).

## Compress

Gzip/Brotli response compression. No configuration needed for the common
case:

```yaml
labels:
  - traefik.http.routers.web.middlewares=compress@docker
  - traefik.http.middlewares.compress.compress=true
```

Optionally exclude content types or set a minimum response size:

```yaml
  - traefik.http.middlewares.compress.compress.minResponseBodyBytes=1024
  - traefik.http.middlewares.compress.compress.excludedContentTypes=image/png,image/jpeg
```

[Docs](https://doc.traefik.io/traefik/middlewares/http/compress/).

## Per-service BasicAuth

Put a login wall in front of a single service (e.g. `pgadmin`, an
internal dashboard). Because the hub terminates TLS, BasicAuth
credentials are encrypted in transit even in local dev — no plaintext
passwords on the wire.

```yaml
labels:
  - traefik.http.routers.pgadmin.middlewares=pgadmin-auth@docker
  - traefik.http.middlewares.pgadmin-auth.basicauth.users=admin:$$2y$$05$$EXAMPLEHASHREPLACEME
```

Generate the hash with `htpasswd` (from `apache2-utils` on Debian,
`httpd-tools` on RHEL):

```bash
htpasswd -nB admin
# admin:$2y$05$abcdef....
```

Then **double every `$`** when pasting into compose — compose interprets
`$` as variable expansion. `$2y$05$...` becomes `$$2y$$05$$...`. A one-liner:

```bash
htpasswd -nB admin | sed -e 's/\$/\$\$/g'
```

For multiple users, separate with commas inside the label value.
[Docs](https://doc.traefik.io/traefik/middlewares/http/basicauth/).

## Retry

Useful when a dev upstream is flaky or slow to come up after
`docker compose restart`:

```yaml
labels:
  - traefik.http.routers.api.middlewares=api-retry@docker
  - traefik.http.middlewares.api-retry.retry.attempts=3
  - traefik.http.middlewares.api-retry.retry.initialInterval=200ms
```

`initialInterval` uses exponential backoff between attempts.  Retries only
fire on connection errors, not on non-2xx responses.
[Docs](https://doc.traefik.io/traefik/middlewares/http/retry/).

## Parking lot

Traefik v3 also ships **RateLimit** and **CircuitBreaker** middlewares.
Both work fine but tend to mask bugs in local dev — a flaky upstream
silently 503s instead of surfacing the real error, or legitimate hot
reloads trip the limiter. Use them in staging/prod, not here. If you do
want rate limiting locally, see the
[Traefik RateLimit docs](https://doc.traefik.io/traefik/middlewares/http/ratelimit/).

## v3 label syntax notes

- **`IPWhiteList` → `IPAllowList`.** Renamed in v3. Old examples on the
  internet still use the v2 name and will silently fail to register.
- **`$` must be doubled in compose.** Any `$` in a label value (bcrypt
  hashes, templated rules) becomes `$$`. This applies to compose files
  only, not the hub's own `docker-compose.yml` command-line flags
  (though it doesn't hurt there either).
- **Label changes aren't picked up on a running container.** Traefik
  hot-reloads its router config when Docker emits events, but
  `docker compose` does not re-push labels to a running container. After
  editing labels, run `docker compose up -d` — compose detects the
  label diff and recreates just that service.
