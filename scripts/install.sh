#!/usr/bin/env bash
# install.sh — install Traefik hub snippets into a consumer project.
#
# Usage (from a local clone of the hub repo):
#   /path/to/traefik_local/scripts/install.sh                 # installs into $PWD
#   /path/to/traefik_local/scripts/install.sh ../my-project   # installs into given dir
#
# Override defaults via env:
#   APP_NAME=myapi APP_PORT=8080 /path/to/install.sh
#
# Or via the hub Makefile:
#   make install TARGET=../my-project APP_NAME=myapi APP_PORT=8080
#
# One-liner (curl from GitHub raw):
#   curl -fsSL https://raw.githubusercontent.com/mechemsi/traefik_local/main/scripts/install.sh \
#     | bash -s -- /path/to/my-project
#
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/mechemsi/traefik_local/main}"

# --- locate snippets (local clone vs piped from curl) ---
SCRIPT_PATH="${BASH_SOURCE[0]:-}"
SNIPPETS_DIR=""
SOURCE_KIND="remote"
if [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
  candidate="$(cd "$(dirname "$SCRIPT_PATH")/.." 2>/dev/null && pwd)/snippets"
  if [ -f "$candidate/traefik.mk" ] && [ -f "$candidate/docker-compose.traefik.yml" ]; then
    SNIPPETS_DIR="$candidate"
    SOURCE_KIND="local"
  fi
fi

# --- target dir ---
target_arg="${1:-$PWD}"
if [ ! -d "$target_arg" ]; then
  echo "Target directory does not exist: $target_arg" >&2
  exit 1
fi
TARGET="$(cd "$target_arg" && pwd)"

APP_NAME="${APP_NAME:-$(basename "$TARGET")}"
APP_PORT="${APP_PORT:-3000}"

echo "Installing Traefik hub snippets"
echo "  target   : $TARGET"
echo "  APP_NAME : $APP_NAME"
echo "  APP_PORT : $APP_PORT"
echo "  source   : $SOURCE_KIND${SNIPPETS_DIR:+ ($SNIPPETS_DIR)}"
echo

prompt_overwrite() {
  local name="$1" ans=n
  if [ -t 0 ]; then
    read -r -p "Overwrite existing $name? [y/N] " ans || ans=n
  else
    { read -r -p "Overwrite existing $name? [y/N] " ans </dev/tty; } 2>/dev/null || ans=n
  fi
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

copy_snippet() {
  local name="$1"
  local dest="$TARGET/$name"
  if [ -f "$dest" ]; then
    if ! prompt_overwrite "$name"; then
      echo "  skip  : $name"
      return 0
    fi
  fi
  if [ "$SOURCE_KIND" = "local" ]; then
    cp "$SNIPPETS_DIR/$name" "$dest"
  else
    if ! command -v curl >/dev/null 2>&1; then
      echo "curl not available; cannot fetch $name remotely." >&2
      exit 1
    fi
    curl -fsSL "$REPO_RAW/snippets/$name" -o "$dest"
  fi
  echo "  wrote : $name"
}

copy_snippet "traefik.mk"
copy_snippet "docker-compose.traefik.yml"

# --- Makefile wiring ---
MK="$TARGET/Makefile"
include_block=$(cat <<EOF

# --- traefik hub integration (added by install.sh) ---
APP_NAME ?= $APP_NAME
APP_PORT ?= $APP_PORT
include traefik.mk
# --- end traefik hub integration ---
EOF
)

if [ -f "$MK" ]; then
  if grep -qE '^[[:space:]]*include[[:space:]]+traefik\.mk[[:space:]]*$' "$MK"; then
    echo "Makefile already includes traefik.mk — leaving Makefile unchanged."
  else
    printf '%s\n' "$include_block" >> "$MK"
    echo "Appended include block to existing Makefile."
  fi
else
  cat > "$MK" <<EOF
.DEFAULT_GOAL := up
$include_block

.PHONY: up down logs
up:   ; \$(COMPOSE) up -d && \$(MAKE) traefik-info
down: ; \$(COMPOSE) down
logs: ; \$(COMPOSE) logs -f
EOF
  echo "Created Makefile with up/down/logs + traefik include."
fi

cat <<EOF

Done. Next:
  1. Open $TARGET/docker-compose.traefik.yml and rename the 'app:' service key
     to match the service name in your base docker-compose.yml.
  2. Make sure the proxy network exists on this machine:
       docker network create proxy   # or 'make network' in the hub repo
  3. cd $TARGET && make up

Hub running? https://$APP_NAME.localhost
Hub down?    http://localhost:$APP_PORT  (fallback)
EOF
