# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Makefile                                           :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/22 22:27:32 by ghenriqu          #+#    #+#              #
#    Updated: 2026/08/01 21:17:46 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

# ---------------------------------------------------------------------------- #
#  Cleanup ladder (what each target destroys)                                  #
#                                                                              #
#    down    containers only                                                   #
#    clean   containers + named volumes + host data under $(DATA_PATH)         #
#    fclean  clean + project images + secrets + /etc/hosts entry               #
#            + dangling images and build cache left behind by THIS project     #
#    prune   GLOBAL docker cleanup: touches every project on the machine.      #
#            Opt-in only, never called by fclean, asks for confirmation.       #
# ---------------------------------------------------------------------------- #

# ============================================================================ #
#  Configuration                                                               #
# ============================================================================ #

PROJECT    := inception

COMPOSE    := srcs/docker-compose.yml
ENV_FILE   := srcs/.env
ENV_SAMPLE := srcs/.env.example

DC     := docker compose -p $(PROJECT) -f $(COMPOSE) --env-file $(ENV_FILE)

DC_ALL := $(DC) --profile bonus

env_get = $(strip $(shell sed -n 's/^$(1)=//p' $(ENV_FILE) 2>/dev/null | tr -d '\r"' | head -n1))

DATA_PATH    	:= $(patsubst %/,%,$(call env_get,DATA_PATH))
DOMAIN_NAME  	:= $(call env_get,DOMAIN_NAME)
WP_ADMIN_USER	:= $(call env_get,WP_ADMIN_USER)
KUMA_ADMIN_USER := $(call env_get,KUMA_ADMIN_USER)

DATA_DIRS  := $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress $(DATA_PATH)/uptime-kuma
CLEAN_DIRS := $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress

SECRETS_DIR := secrets
SECRETS     := $(SECRETS_DIR)/db_root_password.txt \
               $(SECRETS_DIR)/db_password.txt \
               $(SECRETS_DIR)/credentials.txt \
               $(SECRETS_DIR)/wp_user_password.txt \
               $(SECRETS_DIR)/redis_password.txt \
               $(SECRETS_DIR)/ftp_password.txt \
               $(SECRETS_DIR)/kuma_password.txt

HOSTS_TAG  := \# inception
HOSTS_LINE := 127.0.0.1 $(DOMAIN_NAME) adminer.$(DOMAIN_NAME) website.$(DOMAIN_NAME) uptime.$(DOMAIN_NAME)

.DEFAULT_GOAL := all
MAKEFLAGS     += --no-print-directory

# ============================================================================ #
#  Lifecycle                                                                   #
# ============================================================================ #

all: check-docker check-env dirs secrets hosts up
	@$(MAKE) info

bonus: check-docker check-env dirs secrets hosts up-bonus kuma-provision
	@$(MAKE) info

up:
	$(DC) up -d --build --remove-orphans

up-bonus:
	$(DC_ALL) up -d --build --remove-orphans

build: check-env
	$(DC) build

build-bonus: check-env
	$(DC_ALL) build

stop:
	$(DC_ALL) stop

start:
	$(DC_ALL) start

restart:
	$(DC_ALL) restart

# ============================================================================ #
#  Host provisioning                                                           #
# ============================================================================ #

dirs: check-env
	@mkdir -p $(DATA_DIRS)
	@echo "[make] data directories ready under $(DATA_PATH)"

secrets:
	@mkdir -p $(SECRETS_DIR)
	@chmod 700 $(SECRETS_DIR)
	@for f in $(SECRETS); do \
		if [ ! -s "$$f" ]; then \
			openssl rand -base64 24 | tr -d '\n' > "$$f"; \
			chmod 600 "$$f"; \
			echo "[make] secret created: $$f"; \
		fi; \
	done
	@echo "[make] secrets ready (WordPress admin password: cat $(SECRETS_DIR)/credentials.txt)"

kuma-provision:
	@docker exec \
		-e DOMAIN_NAME=$(DOMAIN_NAME) \
		-e KUMA_ADMIN_USER=$(KUMA_ADMIN_USER) \
		uptime-kuma node /app/extra/provision.js

hosts: check-env
	@sudo sed -i '/$(HOSTS_TAG)$$/d' /etc/hosts
	@echo "$(HOSTS_LINE) $(HOSTS_TAG)" | sudo tee -a /etc/hosts > /dev/null
	@echo "[make] /etc/hosts updated for $(DOMAIN_NAME)"

unhosts:
	@sudo sed -i '/$(HOSTS_TAG)$$/d' /etc/hosts
	@echo "[make] /etc/hosts entry removed"

# ============================================================================ #
#  Sanity checks                                                               #
# ============================================================================ #

check-docker:
	@docker info >/dev/null 2>&1 || { \
		echo "ERROR: cannot talk to the Docker daemon."; \
		echo "       Try: sudo systemctl start docker  (and check you belong to the 'docker' group)"; \
		exit 1; }
	@docker compose version >/dev/null 2>&1 || { \
		echo "ERROR: the 'docker compose' v2 plugin is not installed."; exit 1; }

check-env:
	@test -f $(ENV_FILE) || { \
		echo "ERROR: $(ENV_FILE) missing. Run: cp $(ENV_SAMPLE) $(ENV_FILE)"; exit 1; }
	@test -n "$(DOMAIN_NAME)" || { \
		echo "ERROR: DOMAIN_NAME is not set in $(ENV_FILE)"; exit 1; }
	@test -n "$(DATA_PATH)" || { \
		echo "ERROR: DATA_PATH is not set in $(ENV_FILE)"; exit 1; }
	@case "$(DATA_PATH)" in \
		/?*) ;; \
		*) echo "ERROR: DATA_PATH must be an absolute path (got: '$(DATA_PATH)')"; exit 1;; \
	esac
	@case "$(DATA_PATH)" in \
		/|/home|/root|/usr|/var|/etc|"$$HOME") \
			echo "ERROR: refusing to use '$(DATA_PATH)' as DATA_PATH (rm -rf guard)"; exit 1;; \
	esac
	@case "$$(echo '$(WP_ADMIN_USER)' | tr 'A-Z' 'a-z')" in \
		*admin*) echo "ERROR: WP_ADMIN_USER='$(WP_ADMIN_USER)' contains 'admin', which the subject forbids"; exit 1;; \
	esac

# ============================================================================ #
#  Teardown                                                                    #
# ============================================================================ #

down:
	$(DC_ALL) down --remove-orphans
	@echo "[make] containers removed, volumes and host data kept"

clean: check-env
	$(DC_ALL) down -v --remove-orphans
	@sudo rm -rf $(CLEAN_DIRS)
	@sudo rm -rf $(DATA_PATH)/uptime-kuma
	@echo "[make] volumes and host data under $(DATA_PATH) removed"

fclean: clean
	$(DC_ALL) down --rmi all 2>/dev/null || true
	@sudo rm -rf $(DATA_PATH)/uptime-kuma
	@echo "[make] images and all host data removed"

re: clean all

legacy-clean:
	-@docker compose -p srcs -f $(COMPOSE) --env-file $(ENV_FILE) --profile bonus \
		down -v --rmi all --remove-orphans 2>/dev/null
	@echo "[make] legacy 'srcs' project cleaned"

# ============================================================================ #
#  Global cleanup (DANGEROUS - opt-in only)                                    #
# ============================================================================ #

prune:
	@echo "WARNING: this removes unused images, volumes, networks and the build"
	@echo "         cache of EVERY Docker project on this machine, not only Inception."
	@printf "Type 'yes' to continue: "; \
	read ans; \
	[ "$$ans" = "yes" ] || { echo "aborted."; exit 1; }
	docker system prune -af --volumes
	docker builder prune -af

# ============================================================================ #
#  Inspection                                                                  #
# ============================================================================ #

ps:
	$(DC_ALL) ps

logs:
	$(DC_ALL) logs -f

info:
	@echo ""
	@echo "  site      https://$(DOMAIN_NAME)"
	@echo "  wp-admin  https://$(DOMAIN_NAME)/wp-admin   (user: $(WP_ADMIN_USER))"
	@echo "  adminer   https://adminer.$(DOMAIN_NAME)    [bonus]"
	@echo "  website   https://website.$(DOMAIN_NAME)    [bonus]"
	@echo "  uptime    https://uptime.$(DOMAIN_NAME)     [bonus]"
	@echo "  ftp       ftps://$(DOMAIN_NAME):21          [bonus]"
	@echo ""
	@echo "  secrets   $(SECRETS_DIR)/     data  $(DATA_PATH)/"
	@echo ""
	@$(DC_ALL) ps

help:
	@grep -hE '^[a-zA-Z_%-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

.PHONY: all bonus up up-bonus build build-bonus stop start restart \
        dirs secrets hosts unhosts check-docker check-env \
        down clean fclean re legacy-clean prune \
        ps logs info help
