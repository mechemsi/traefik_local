# Local HTTPS via mkcert

Cheat-sheet for the one-time cert setup. When you're done, `*.localhost`
is served over HTTPS with a locally-trusted cert and HTTP auto-redirects.

## What you get

The hub terminates TLS on `:443` with a wildcard cert covering
`*.localhost`. Every router attached to the hub — `traefik.localhost`,
`myapp.localhost`, `whoami.localhost`, ... — is reachable at
`https://...` with a green padlock in Chrome, Edge, and Firefox. HTTP
requests are redirected to HTTPS at the entrypoint level, so no per-router
config is needed.

Secure context unlocks browser APIs that silently refuse to run on plain
HTTP: service workers, `crypto.subtle` (WebCrypto), WebAuthn, the async
clipboard API, geolocation, sensors, and most of the "powerful features"
list. Useful the first time you try to test one of those locally.

## Why mkcert, not Let's Encrypt

`.localhost` is reserved by [RFC 6761 §6.3](https://datatracker.ietf.org/doc/html/rfc6761#section-6.3).
No public CA will ever issue a cert for it, so ACME (Let's Encrypt) is
not an option. [mkcert](https://github.com/FiloSottile/mkcert) solves
exactly this: it creates a local root CA, installs it into your OS (and
browser) trust stores, then mints leaf certs signed by that CA. Trust is
scoped to your machine — nobody else can MITM you with a mkcert cert.

## Prerequisite: install mkcert

**WSL (Debian/Ubuntu):**

```bash
sudo apt install mkcert libnss3-tools
```

`libnss3-tools` pulls in `certutil`, which mkcert needs to trust the CA
for Firefox and Chromium-family browsers that ship their own NSS DB.

**Windows (PowerShell):**

```powershell
winget install FiloSottile.mkcert
choco install nss    # provides certutil.exe; needed for Firefox trust
```

If you don't use Firefox, `nss` is optional — but installing it is
cheaper than debugging cert warnings later.

## One-time CA install (WSL2 + Windows dual-trust)

Browsers run on Windows; CLI tools (`curl`, `wget`, `git`) run in WSL.
Both need to trust the same root CA. There is **one** CA, shared across
the boundary via the `CAROOT` env var — don't run `mkcert -CAROOT` on
both sides and end up with two different roots.

1. **In PowerShell on Windows** (not WSL), run:

   ```powershell
   mkcert -install
   ```

   This writes the mkcert root CA into the Windows certificate store
   (picked up by Chrome, Edge, and `curl.exe`) and the Firefox NSS DB
   (if `certutil.exe` is on PATH).

2. Find where mkcert stores the CA files:

   ```powershell
   mkcert -CAROOT
   # Typically: C:\Users\<you>\AppData\Local\mkcert
   ```

3. Share the path into WSL via `WSLENV` so the WSL-side mkcert reuses
   the same CA instead of making a new one. In PowerShell:

   ```powershell
   setx WSLENV "$env:WSLENV`:CAROOT/up"
   ```

   The `/up` flag translates the Windows path to a `/mnt/c/...` path
   when entering WSL. Restart WSL for the change to take effect:

   ```powershell
   wsl --shutdown
   ```

4. **In WSL**, verify the CA is visible:

   ```bash
   echo $CAROOT
   # /mnt/c/Users/<you>/AppData/Local/mkcert
   ls "$CAROOT"
   # rootCA.pem  rootCA-key.pem
   ```

5. **In WSL**, install that same CA into the Linux trust stores:

   ```bash
   mkcert -install
   ```

   Now `curl https://foo.localhost` from WSL trusts the cert, same as
   Chrome on Windows.

## Generate the hub's cert

```bash
cd ~/traefik
make certs
```

Under the hood `make certs` runs:

```bash
mkcert -cert-file certs/localhost.pem \
       -key-file  certs/localhost-key.pem \
       localhost "*.localhost" 127.0.0.1 ::1
```

The quotes around `*.localhost` stop the shell from glob-expanding the
`*`. The two files land in `./certs/`, which is gitignored. Traefik picks
them up via the file provider (`dynamic/tls.yml`).

## Bring up the hub

```bash
make up
open https://traefik.localhost
```

`make up` refuses to start if `certs/localhost.pem` is missing — run
`make certs` first. HTTP is redirected to HTTPS at the entrypoint, so
`http://traefik.localhost` lands at the HTTPS dashboard.

## Firefox specifics

If Firefox shows "Warning: Potential Security Risk Ahead" after
`mkcert -install` succeeded elsewhere, `certutil.exe` was almost
certainly missing on PATH when `mkcert -install` ran on Windows. Fix:

```powershell
choco install nss
mkcert -install        # re-run now that certutil is available
```

Restart Firefox fully (not just the tab). Chromium-family browsers on
Linux have the same dependency on the WSL side; `libnss3-tools` from
the prerequisites step covers it.

## Cert renewal and extra hostnames

mkcert leaf certs are valid for 2+ years; you won't rotate them often.
If you want to cover a new TLD (`*.test`, `*.dev`) or a specific extra
name, re-run `make certs` with the extra SANs appended. Since Traefik's
file provider is watching `dynamic/tls.yml` with `--providers.file.watch=true`,
new cert files are hot-reloaded — no `make restart` needed.

The root CA itself is valid for 10 years. Renew with `mkcert -install`
(re-runs are idempotent) when it eventually expires.

## Troubleshooting

- **"cert not trusted" from WSL `curl`, but browser is fine** — you ran
  `mkcert -install` on Windows only. Re-run it inside WSL.
- **"cert not trusted" in Firefox on Windows** — `certutil.exe` was
  missing when `mkcert -install` ran. Install NSS, re-run, restart
  Firefox.
- **`make up` fails with "certs missing"** — run `make certs` first.
- **Chrome keeps showing a warning even after `-install`** — Chrome
  caches the OS trust store at startup. Quit Chrome completely (check
  Task Manager for leftover processes on Windows) and reopen.
- **`ERR_SSL_PROTOCOL_ERROR` on localhost** — verify Windows is patched
  past the November 2025 cumulative rollup; the October 2025 KB5066835
  update broke loopback HTTP/2. See the research doc.
- **Cert presented is for `traefik.localhost` when you asked for
  `myapp.localhost`** — the default cert is being served because
  Traefik has no router for that host. Usually means the consumer
  container isn't on the `proxy` network or lacks `traefik.enable=true`.
  Check `make status` and `docker inspect <container> | grep traefik`.
- **`CAROOT` is empty in WSL** — the `WSLENV` edit didn't stick. Re-run
  `setx WSLENV ...` in PowerShell, then `wsl --shutdown` and reopen WSL.

## References

- [mkcert repo](https://github.com/FiloSottile/mkcert)
- [mkcert issue #357 — WSL install notes](https://github.com/FiloSottile/mkcert/issues/357)
- [Traefik v3 TLS reference](https://doc.traefik.io/traefik/https/tls/)
- [Traefik v3 file provider](https://doc.traefik.io/traefik/providers/file/)
