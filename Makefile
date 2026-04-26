.DEFAULT_GOAL := help

COMPOSE := docker compose
NETWORK := proxy

.PHONY: help
help:
	@echo "Local Traefik dev hub"
	@echo ""
	@echo "Targets:"
	@echo "  make network         Create the shared '$(NETWORK)' docker network (idempotent)"
	@echo "  make up              Ensure network, then bring Traefik up"
	@echo "  make down            Stop Traefik"
	@echo "  make restart         Restart Traefik"
	@echo "  make logs            Tail Traefik logs"
	@echo "  make status          Show hub status and routed apps"
	@echo "  make lint            Validate every compose file in the repo"
	@echo "  make install TARGET=<path>"
	@echo "                       Install snippets into a consumer project"
	@echo "                       (optional: APP_NAME=<name> APP_PORT=<port>)"
	@echo "  make install-skills  Symlink ./skills/* into ~/.claude/skills/"
	@echo "                       (Claude Code picks them up globally)"
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

.PHONY: install
install:
	@if [ -z "$(TARGET)" ]; then \
	  echo "Usage: make install TARGET=<path-to-consumer-project> [APP_NAME=<name>] [APP_PORT=<port>]"; \
	  exit 1; \
	fi
	@APP_NAME='$(APP_NAME)' APP_PORT='$(APP_PORT)' ./scripts/install.sh '$(TARGET)'

.PHONY: lint
lint:
	@echo "Linting hub compose..."
	@DASHBOARD_AUTH=lint-placeholder $(COMPOSE) -f docker-compose.yml config --quiet
	@echo "Linting example: whoami..."
	@cd examples/whoami && APP_NAME=whoami APP_HOST=whoami.localhost APP_PORT=80 \
	  docker compose -f docker-compose.yml -f docker-compose.traefik.yml config --quiet
	@echo "All compose files parse cleanly."

# Symlink each skill in ./skills/ into ~/.claude/skills/ so Claude Code
# auto-discovers them globally. Symlinks (not copies) keep the user's
# install in sync with `git pull` of this repo.
SKILLS_SRC := $(CURDIR)/skills
SKILLS_DST := $(HOME)/.claude/skills

.PHONY: install-skills
install-skills:
	@if [ ! -d "$(SKILLS_SRC)" ]; then \
	  echo "No skills/ directory at $(SKILLS_SRC)."; exit 1; \
	fi
	@mkdir -p "$(SKILLS_DST)"
	@for dir in "$(SKILLS_SRC)"/*/; do \
	  name=$$(basename "$$dir"); \
	  case "$$name" in _*) continue ;; esac; \
	  dst="$(SKILLS_DST)/$$name"; \
	  if [ -L "$$dst" ]; then \
	    cur=$$(readlink "$$dst"); \
	    if [ "$$cur" = "$$dir" ] || [ "$$cur" = "$${dir%/}" ]; then \
	      echo "  ok    : $$name (already linked)"; continue; \
	    fi; \
	    echo "  warn  : $$name -> $$cur (different target; leaving as-is)"; continue; \
	  fi; \
	  if [ -e "$$dst" ]; then \
	    echo "  warn  : $$name exists and is not a symlink (leaving as-is)"; continue; \
	  fi; \
	  ln -s "$${dir%/}" "$$dst"; \
	  echo "  link  : $$name -> $${dir%/}"; \
	done
	@echo ""
	@echo "Skills installed to $(SKILLS_DST). Restart Claude Code to pick them up."

.PHONY: uninstall-skills
uninstall-skills:
	@for dir in "$(SKILLS_SRC)"/*/; do \
	  name=$$(basename "$$dir"); \
	  case "$$name" in _*) continue ;; esac; \
	  dst="$(SKILLS_DST)/$$name"; \
	  if [ -L "$$dst" ]; then \
	    cur=$$(readlink "$$dst"); \
	    if [ "$$cur" = "$$dir" ] || [ "$$cur" = "$${dir%/}" ]; then \
	      rm "$$dst"; echo "  unlink: $$name"; \
	    else \
	      echo "  skip  : $$name (-> $$cur, not ours)"; \
	    fi; \
	  fi; \
	done
