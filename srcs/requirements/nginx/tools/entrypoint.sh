#!/bin/bash

# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    entrypoint.sh                                      :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/10 18:49:10 by ghenriqu          #+#    #+#              #
#    Updated: 2026/05/16 21:15:37 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

set -e

if [ ! -f /etc/nginx/ssl/server.crt ] || [ ! -f /etc/nginx/ssl/server.key ]; then
    echo "ERROR: TLS material missing in /etc/nginx/ssl/" >&2
    echo "       Expected: server.crt and server.key"     >&2
    exit 1
fi

echo "TLS material OK. Starting nginx..."

exec nginx -g 'daemon off;'
