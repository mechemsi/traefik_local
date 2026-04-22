.DEFAULT_GOAL := help

COMPOSE := docker compose
NETWORK := proxy

.PHONY: help
help:
	@echo "Local Traefik dev hub"
	@echo ""
	@echo "Targets:"
	@echo "  make network   Create the shared '$(NETWORK)' docker network (idempotent)"
	@echo "  make up        Ensure network, then bring Traefik up"
	@echo "  make down      Stop Traefik"
	@echo "  make restart   Restart Traefik"
	@echo "  make logs      Tail Traefik logs"
	@echo "  make status    Show hub status and routed apps"
	@echo ""
	@echo "Dashboard: http://traefik.localhost (when up)"

.PHONY: network
network:
	@docker network inspect $(NETWORK) >/dev/null 2>&1 \
	  || docker network create $(NETWORK)

.PHONY: up
up: network
	$(COMPOSE) up -d
	@echo ""
	@echo "Dashboard: http://traefik.localhost"

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
