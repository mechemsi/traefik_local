.DEFAULT_GOAL := help

COMPOSE := docker compose
NETWORK := proxy

.PHONY: help
help:
	@echo "Local Traefik dev hub"
	@echo ""
	@echo "Targets:"
	@echo "  make network   Create the shared '$(NETWORK)' docker network (idempotent)"
	@echo "  make certs     Generate local HTTPS certs via mkcert (./certs/)"
	@echo "  make up        Ensure network + certs, then bring Traefik up"
	@echo "  make down      Stop Traefik"
	@echo "  make restart   Restart Traefik"
	@echo "  make logs      Tail Traefik logs"
	@echo "  make status    Show hub status and routed apps"
	@echo "  make lint      Validate every compose file in the repo"
	@echo ""
	@echo "Dashboard: https://traefik.localhost (when up)"

.PHONY: network
network:
	@docker network inspect $(NETWORK) >/dev/null 2>&1 \
	  || docker network create $(NETWORK)

.PHONY: certs
certs:
	@command -v mkcert >/dev/null 2>&1 || { \
	  echo "mkcert not found on PATH."; \
	  echo "Install: 'sudo apt install mkcert' (Debian/Ubuntu) — see docs/https.md."; \
	  echo "After install, run 'mkcert -install' once (modifies system trust store)."; \
	  exit 1; \
	}
	@mkdir -p certs
	mkcert -cert-file certs/localhost.pem -key-file certs/localhost-key.pem localhost "*.localhost" 127.0.0.1 ::1
	@echo ""
	@echo "Certs written to ./certs/. Remember: 'mkcert -install' once for browser trust."

.PHONY: check-certs
check-certs:
	@if [ ! -f certs/localhost.pem ] || [ ! -f certs/localhost-key.pem ]; then \
	  echo "Missing certs at ./certs/localhost.pem or ./certs/localhost-key.pem."; \
	  echo "Run 'make certs' to generate them (see docs/https.md)."; \
	  exit 1; \
	fi

.PHONY: up
up: network check-certs
	$(COMPOSE) up -d
	@echo ""
	@echo "Dashboard: https://traefik.localhost"

.PHONY: down
down:
	$(COMPOSE) down

.PHONY: restart
restart: down up

.PHONY: logs
logs:
	$(COMPOSE) logs -f traefik

.PHONY: status
status:
	@running=$$(docker inspect -f '{{.State.Running}}' traefik 2>/dev/null); \
	 if [ "$$running" = "true" ]; then \
	   echo "Traefik: running"; \
	 else \
	   echo "Traefik: not running"; \
	 fi
	@echo ""
	@echo "Containers labeled for Traefik on network '$(NETWORK)':"
	@docker ps --filter "network=$(NETWORK)" --filter "label=traefik.enable=true" \
	  --format '  - {{.Names}}  ({{.Image}})' || true

.PHONY: lint
lint:
	@echo "Linting hub compose..."
	@DASHBOARD_AUTH=lint-placeholder $(COMPOSE) -f docker-compose.yml config --quiet
	@echo "Linting example: whoami..."
	@cd examples/whoami && APP_NAME=whoami APP_HOST=whoami.localhost APP_PORT=80 \
	  docker compose -f docker-compose.yml -f docker-compose.traefik.yml config --quiet
	@echo "All compose files parse cleanly."
