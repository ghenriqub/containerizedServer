#!/bin/bash

# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    init.sh                                            :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/08/01 15:44:08 by ghenriqu          #+#    #+#              #
#    Updated: 2026/08/01 15:44:09 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

set -eu

DOCROOT="/var/www/website"

if [ ! -s "${DOCROOT}/index.html" ]; then
    echo "ERROR: ${DOCROOT}/index.html missing or empty." >&2
    echo "       Check srcs/requirements/bonus/website/site/ and .dockerignore." >&2
    exit 1
fi

nginx -t -q

echo "[website] starting nginx on 0.0.0.0:8080 as www-data (PID 1)..."

exec nginx -g 'daemon off;'

