#!/usr/bin/env bash
# Bring the Traefik hub up once per WSL session, after Docker is ready.
#
# Wired from ~/.bashrc:
#   [ -x ~/traefik/scripts/autostart.sh ] && ~/traefik/scripts/autostart.sh &
#
# The /tmp marker makes this a no-op on every shell after the first; /tmp
# is wiped when WSL restarts, so the next boot re-runs it.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MARKER=/tmp/traefik-autostart.done
LOG=/tmp/traefik-autostart.log
WAIT_SECS=60

[ -f "$MARKER" ] && exit 0

exec >>"$LOG" 2>&1
echo "--- $(date -Iseconds) autostart begin ---"

for i in $(seq 1 "$WAIT_SECS"); do
  if docker info >/dev/null 2>&1; then
    echo "docker ready after ${i}s"
    break
  fi
  if [ "$i" -eq "$WAIT_SECS" ]; then
    echo "docker not ready after ${WAIT_SECS}s, giving up"
    exit 1
  fi
  sleep 1
done

cd "$REPO_DIR"
make restart
touch "$MARKER"
echo "--- $(date -Iseconds) autostart done ---"
