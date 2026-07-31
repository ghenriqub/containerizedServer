#!/bin/bash

# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    init.sh                                            :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/31 11:41:57 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/31 11:42:08 by ghenriqu         ###   ########.fr        #
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

exec setpriv --reuid=www-data --regid=www-data --init-groups \
     nginx -g 'daemon off;'
