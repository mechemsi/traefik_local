# traefik.mk — drop-in Makefile include for consumer projects.
#
# Usage (in the consumer project's Makefile):
#
#     APP_NAME ?= myapp          # used for traefik router/service names
#     APP_PORT ?= 3000           # the port your service listens on inside the container
#     # APP_HOST ?= myapp.localhost   # optional; defaults to <dir-name>.localhost
#     # APP_HOST_PORT ?= 3000         # optional; host-published port for fallback URL.
#     #                                 defaults to APP_PORT. Set it when host:container
#     #                                 differ, e.g. ports: ["8081:80"] -> APP_HOST_PORT=8081
#     include traefik.mk
#
#     up:   ; $(COMPOSE) up -d && $(MAKE) traefik-info
#     down: ; $(COMPOSE) down
#     logs: ; $(COMPOSE) logs -f
#
# Behavior:
#   - If a container named 'traefik' is running, compose is invoked with the
#     base file and docker-compose.traefik.yml (labels + proxy network).
#     The app is reachable at http://$(APP_HOST) (HTTP-only by design).
#     No host port is published in this mode — Traefik reaches the
#     container over the internal `proxy` network.
#   - Otherwise, the base file is layered with docker-compose.fallback.yml,
#     which publishes $(APP_PORT) on the host as $(APP_HOST_PORT). The app
#     is reachable at http://localhost:$(APP_HOST_PORT).
#
#   The base docker-compose.yml should NOT declare `ports:` for the
#   web-facing service — port publishing belongs in the fallback overlay.
#   See docker-compose.fallback.yml for the rationale.

TRAEFIK_CONTAINER ?= traefik
TRAEFIK_RUNNING   := $(shell docker inspect -f '{{.State.Running}}' $(TRAEFIK_CONTAINER) 2>/dev/null)

APP_NAME      ?= $(notdir $(CURDIR))
APP_HOST      ?= $(APP_NAME).localhost
APP_PORT      ?= 3000
APP_HOST_PORT ?= $(APP_PORT)

ifeq ($(TRAEFIK_RUNNING),true)
  COMPOSE_FILES := -f docker-compose.yml -f docker-compose.traefik.yml
  ACCESS_URL    := http://$(APP_HOST)
  TRAEFIK_MODE  := routed via Traefik
else
  COMPOSE_FILES := -f docker-compose.yml -f docker-compose.fallback.yml
  ACCESS_URL    := http://localhost:$(APP_HOST_PORT)
  TRAEFIK_MODE  := fallback (direct port)
endif

export APP_NAME APP_HOST APP_PORT APP_HOST_PORT

COMPOSE := docker compose $(COMPOSE_FILES)

.PHONY: traefik-info
traefik-info:
	@echo "Traefik: $(if $(filter true,$(TRAEFIK_RUNNING)),running,not running)"
	@echo "Mode:    $(TRAEFIK_MODE)"
	@echo "Access:  $(ACCESS_URL)"
