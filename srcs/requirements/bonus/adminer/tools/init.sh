#!/bin/bash

# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    init.sh                                            :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/28 00:00:00 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/28 00:00:00 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

set -eu

mkdir -p /run/php

if [ ! -s /var/www/adminer/index.php ]; then
    echo "ERROR: /var/www/adminer/index.php missing or empty." >&2
    exit 1
fi

echo "[adminer] starting php-fpm on 0.0.0.0:9000 (PID 1)..."

exec /usr/sbin/php-fpm8.2 -F -O
