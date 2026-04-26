# CLAUDE.md

Repo-specific guidance for Claude Code sessions in this directory.
Loaded automatically; keep it tight (every session reads it).

This is a local-only Traefik v3 dev hub. **HTTP-only by design** —
the local TLS trust-store dance was more friction than the value it
delivered. Adding HTTPS back is a structural change; see "Out of
scope" below.

## Architecture invariants

- One `traefik` container, single `web` entrypoint on `:80`.
- Shared `proxy` Docker network, declared `external: true` so multiple
  consumer projects on the machine attach to the same network. **Must
  be created out-of-band** (`make network`) — compose can't manage it.
- Docker provider with `defaultRule = Host(`{{ normalize .Name }}.localhost`)`.
  Caveat — compose v2 names containers `<project>-<service>-N` unless
  `container_name:` is set. Consumer overrides default to an explicit
  `Host()` rule for that reason.
- Hub-up/hub-down toggle in `snippets/traefik.mk` is evaluated at
  **make-time**, not container runtime. Flipping requires re-running
  `make up` in the consumer.
- Three consumer snippets, not two: `snippets/traefik.mk`,
  `snippets/docker-compose.traefik.yml` (routed overlay — labels +
  proxy network, no ports), `snippets/docker-compose.fallback.yml`
  (fallback overlay — `ports:` only). The Makefile picks which overlay
  to apply based on hub state. Consumer base `docker-compose.yml` must
  NOT declare `ports:` for the web-facing service — compose appends
  override ports to base, so a base-level entry would publish in both
  modes and re-introduce host-port collisions across consumers.
- `.env` holds `DASHBOARD_AUTH` (gitignored). Compose interpolation
  requires `$` to be **doubled** in label and `.env` values:
  `htpasswd -nB user | sed -e 's/\$/\$\$/g'`.

## Canonical references (read these before editing)

- `skills/_shared/SNIPPET-CONTRACT.md` — variable contract, the
  container-name trap, v3 label gotchas. **Source of truth** for what
  the snippets do.
- `skills/traefik-integrate-project/SKILL.md` — operator-mode
  consumer wire-up flow.
- `skills/traefik-hub-maintain/SKILL.md` — hub edits + diagnostics.
- `docs/integrating-a-project.md` — human-facing integration guide.
- `docs/middlewares.md` — copy-paste middleware recipes (CORS,
  basicauth, retry, compress).

## When you change X, also update Y

### Hub `docker-compose.yml`
- `command:` flags (entrypoints, providers, defaultRule) → likely also
  `skills/traefik-hub-maintain/SKILL.md` if user-visible.
- Ports / volumes → update README "Scope" if it changes the posture
  (HTTP/HTTPS/auth/persistence).
- Always: `make lint && make restart` and verify
  `curl -sI http://traefik.localhost` returns 401.

### Snippets (`snippets/traefik.mk`, `snippets/docker-compose.traefik.yml`, `snippets/docker-compose.fallback.yml`)
- Update `skills/_shared/SNIPPET-CONTRACT.md` whenever variable names,
  defaults, or behavior change. The shared doc is what both skills
  load as required background.
- Update `docs/integrating-a-project.md` if the change is
  developer-facing (new var, changed default, new label, new overlay).
- Update `examples/whoami/` if the snippet shape changes (whoami is
  the lint target — `make lint` exercises both routed and fallback
  merges). Keep `examples/whoami/traefik.mk` in sync with
  `snippets/traefik.mk` — it's a copy, not a symlink, and goes stale
  silently.
- `make lint` after.

### Makefile
- Update the `make help` block when adding/removing a target.
- Update README quickstart and "Other targets" if the target is
  user-facing.
- For `install-*` targets, ensure idempotency (re-runs must not break).

### Skills (`skills/*/SKILL.md`)
- Skill **descriptions** must describe *triggering conditions only* —
  no workflow summary. Per `superpowers:writing-skills`: a description
  that summarizes the workflow becomes a shortcut Claude takes
  *instead* of reading the full skill body.
- Skill files are symlinked into `~/.claude/skills/` via
  `make install-skills`. Skill **bodies** are read live; **descriptions**
  are cached at Claude Code session start. Description changes need a
  restart to take effect; body changes don't.
- If both skills need to know something (variable contract, gotchas),
  put it in `skills/_shared/SNIPPET-CONTRACT.md` and reference it from
  each skill's "REQUIRED BACKGROUND" line — don't duplicate.

### `scripts/install.sh`
- Update the "Done. Next:" handoff message when the consumer-side
  workflow changes (URL scheme, required edits).
- `REPO_RAW` is hard-coded to `mechemsi/traefik_local`. If the repo
  is forked / renamed, that needs to change for the curl-pipe install
  path.

### CI (`.github/workflows/ci.yml`)
- Three jobs run on every push and PR: `compose-lint` (runs
  `make lint`), `shellcheck` (`scripts/install.sh`), `gitleaks` (full
  history secret scan).
- No custom `.gitleaks.toml`. Defaults are fine for this repo. Only
  add an allowlist if CI false-positives.
- Pin actions by major version (`@v4`, `@v2`). SHA-pinning is overkill
  here; this is a local-dev hub.

## Out of scope (don't propose without discussion)

- **Adding HTTPS back.** Posture is deliberate (commit `5bbc40c`).
  If a real use case emerges (browser secure-context APIs, encrypted
  basicauth), raise it as a design discussion first — not a routine
  edit.
- **New entrypoints / providers / `defaultRule` changes.** Repo-shaped
  decisions; brainstorm + PR review, not skill territory.
- **Production Traefik patterns** (ACME, multi-host, TLS). This is a
  local dev hub; production is a different repo.

## Conventions

- **Don't commit unless explicitly asked.** Stage and verify, then
  surface the diff and wait.
- `make lint` must stay green. CI enforces it; treat a red lint as a
  build break, not a warning.
- `.env` is gitignored. Never include `DASHBOARD_AUTH` values, hashes,
  or other secrets in commits or PRs (gitleaks CI will catch most,
  but pre-commit review is cheaper).
- When adding files, match the existing convention: tracked snippets
  go in `snippets/`, executable scripts in `scripts/`, skill content
  in `skills/<name>/SKILL.md`.
- Don't add backwards-compatibility shims for removed config or
  removed targets. Delete cleanly; the git log preserves history.

## Hard-won context (the things that bit us)

- **Container-name mangling** is the #1 silent failure for consumers.
  See SNIPPET-CONTRACT.md.
- **`$$` doubling** is mandatory in any compose-interpolated value.
  Common with htpasswd basicauth hashes; one-liner sed handles it.
- **HSTS bite-back**: browsers that previously hit a `<host>.localhost`
  over HTTPS will keep auto-upgrading even after the hub goes
  HTTP-only. Fix: `chrome://net-internals/#hsts` "Delete domain
  security policies".
- **Service-name mismatch**: forgetting to rename `app:` → real
  service name in the consumer override is silent — labels go to a
  phantom `app:` service and the real service stays unrouted. Catch
  with `docker compose config`.
