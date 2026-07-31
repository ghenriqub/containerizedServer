#!/bin/bash

# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    init.sh                                            :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/31 12:40:28 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/31 12:41:29 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

set -eu

DATA_DIR="/app/data"

mkdir -p "${DATA_DIR}"
chown -R kuma:kuma "${DATA_DIR}"

if [ ! -f /app/server/server.js ]; then
    echo "ERROR: /app/server/server.js not found." >&2
    echo "       The build stage did not complete (out of memory?)." >&2
    exit 1
fi

echo "[uptime-kuma] starting node on ${UPTIME_KUMA_HOST}:${UPTIME_KUMA_PORT} as kuma (PID 1)..."

exec setpriv --reuid=kuma --regid=kuma --init-groups \
     node server/server.js
