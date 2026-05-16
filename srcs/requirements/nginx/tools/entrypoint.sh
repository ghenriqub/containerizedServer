# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    entrypoint.sh                                      :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/05/10 18:49:10 by ghenriqu          #+#    #+#              #
#    Updated: 2026/05/16 17:21:11 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

set -e

envsubst '$DOMAIN_NAME' < /etc/nginx/nginx.conf > /tmp/nginx.conf

mv /tmp/nginx.conf /etc/nginx/nginx.conf

echo "Resolved DOMAIN_NAME=${DOMAIN_NAME} in nginx.conf"

if [ ! -f /etc/nginx/ssl/server.crt ] || [ ! -f /etc/nginx/ssl/server.key ]; then
    echo "Error: TLS certificate or key not found at /etc/nginx/ssl/"
    echo "Expected files: server.crt, server.key"
    echo "These should have been generated during docker build."
    exit 1
fi

echo "TLS certificate found. Starting NGINX..."

exec nginx -g 'daemon off;'
