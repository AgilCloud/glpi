COMPOSE ?= docker compose
SERVICE ?= glpi

.PHONY: build up down logs shell restart clean healthcheck install setup-env

build:
	$(COMPOSE) build

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=200

shell:
	$(COMPOSE) exec $(SERVICE) sh

restart:
	$(COMPOSE) restart

clean:
	$(COMPOSE) down -v --remove-orphans

healthcheck:
	$(COMPOSE) ps
	$(COMPOSE) exec db healthcheck.sh --connect --innodb_initialized
	@curl -fsS "http://localhost:$${GLPI_HTTP_PORT:-8080}/" >/dev/null

install: setup-env build up

setup-env:
	@if [ -f .env ]; then \
		echo ".env already exists; keeping current file."; \
	else \
		cp .env.example .env; \
		echo "Created .env from .env.example."; \
	fi
