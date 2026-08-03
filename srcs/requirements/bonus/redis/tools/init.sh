#!/bin/bash

# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    init.sh                                            :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/08/01 15:40:59 by ghenriqu          #+#    #+#              #
#    Updated: 2026/08/01 15:41:00 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

set -eu

CONF_TEMPLATE="/etc/redis/redis.conf"
RUNTIME_CONF="/run/redis/redis.conf"
SECRET_FILE="/run/secrets/redis_password"

if [ ! -s "${SECRET_FILE}" ]; then
    echo "ERROR: ${SECRET_FILE} missing or empty." >&2
    exit 1
fi

mkdir -p /run/redis
cp "${CONF_TEMPLATE}" "${RUNTIME_CONF}"
printf 'requirepass %s\n' "$(cat "${SECRET_FILE}")" >> "${RUNTIME_CONF}"

chown -R redis:redis /run/redis /var/lib/redis
chmod 700 /run/redis
chmod 600 "${RUNTIME_CONF}"

echo "[redis] starting redis-server as PID 1 (user: redis)..."

exec setpriv --reuid=redis --regid=redis --init-groups \
     redis-server "${RUNTIME_CONF}"
