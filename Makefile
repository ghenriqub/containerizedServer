# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Makefile                                           :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/22 22:27:32 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/31 14:21:54 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

# ---------------------------------------------------------------------------- #
#  Variables                                                                   #
# ---------------------------------------------------------------------------- #
COMPOSE   := srcs/docker-compose.yml
ENV_FILE  := srcs/.env

DC        := docker compose -f $(COMPOSE) --env-file $(ENV_FILE)

DATA_PATH   := $(shell grep -E '^DATA_PATH='   $(ENV_FILE) | cut -d '=' -f2-)
DOMAIN_NAME := $(shell grep -E '^DOMAIN_NAME=' $(ENV_FILE) | cut -d '=' -f2-)

SECRETS_DIR := secrets
SECRETS     := $(SECRETS_DIR)/db_root_password.txt \
               $(SECRETS_DIR)/db_password.txt \
               $(SECRETS_DIR)/credentials.txt \
               $(SECRETS_DIR)/wp_user_password.txt \
               $(SECRETS_DIR)/redis_password.txt \
			   $(SECRETS_DIR)/ftp_password.txt

HOSTS_LINE := 127.0.0.1 $(DOMAIN_NAME) adminer.$(DOMAIN_NAME) website.$(DOMAIN_NAME) uptime.$(DOMAIN_NAME)

all: check-env dirs secrets hosts up

check-env:
	@test -f $(ENV_FILE) || { \
		echo "ERROR: $(ENV_FILE) doesn't exist. Check srcs/.env.example."; exit 1; }

# ---------------------------------------------------------------------------- #
#  Host provisioning                                                           #
# ---------------------------------------------------------------------------- #
dirs:
	@mkdir -p $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress $(DATA_PATH)/uptime-kuma
	@echo "[make] dirs OK in $(DATA_PATH)"

secrets:
	@mkdir -p $(SECRETS_DIR)
	@for f in $(SECRETS); do \
		if [ ! -s "$$f" ]; then \
			openssl rand -base64 24 | tr -d '\n' > "$$f"; \
			chmod 600 "$$f"; \
			echo "[make] secret created: $$f"; \
		fi; \
	done
	@echo "[make] WP admin password -> cat $(SECRETS_DIR)/credentials.txt"

hosts:
	@grep -qxF "$(HOSTS_LINE)" /etc/hosts || \
		echo "$(HOSTS_LINE)" | sudo tee -a /etc/hosts > /dev/null
	@echo "[make] /etc/hosts OK ($(HOSTS_LINE))"

# ---------------------------------------------------------------------------- #
#  Lifecycle.                                                                  #
# ---------------------------------------------------------------------------- #
up:
	$(DC) up -d --build

bonus: check-env dirs secrets hosts
	$(DC) --profile bonus up -d --build

down:
	$(DC) down

clean:
	$(DC) down -v

re: clean all

fclean: clean
	$(DC) down --rmi all 2>/dev/null || true
	@sudo rm -rf $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress $(DATA_PATH)/uptime-kuma
	@echo "[make] dados do host removidos."

ps:
	$(DC) ps
logs:
	$(DC) logs -f

.PHONY: all check-env dirs secrets hosts up bonus down clean re fclean ps logs
