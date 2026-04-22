# Example consumer Makefile. Demonstrates the traefik.mk drop-in.
#
# - With the hub running:    http://whoami.localhost
# - With the hub not running: http://localhost:8081

APP_NAME      ?= whoami
APP_HOST      ?= whoami.localhost
APP_PORT      ?= 80       # in-container port (traefik/whoami listens on :80)
APP_HOST_PORT ?= 8081     # host-published port (see ports: in docker-compose.yml)

include traefik.mk

.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "whoami example"
	@echo ""
	@echo "  make up     Start whoami (auto-detects hub)"
	@echo "  make down   Stop whoami"
	@echo "  make logs   Tail whoami logs"
	@echo "  make info   Show current mode and access URL"

.PHONY: up
up:
	$(COMPOSE) up -d
	@$(MAKE) --no-print-directory traefik-info

.PHONY: down
down:
	$(COMPOSE) down

.PHONY: logs
logs:
	$(COMPOSE) logs -f

.PHONY: info
info: traefik-info
