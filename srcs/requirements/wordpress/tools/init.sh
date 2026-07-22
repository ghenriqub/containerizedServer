#!/bin/bash

# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    init.sh                                            :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/22 22:43:56 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/22 22:44:10 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

set -e

mkdir -p /run/php

echo "Waiting for MariaDB to be ready..."
for i in $(seq 1 30); do
    if mariadb-admin ping -h mariadb -u"${MYSQL_USER}" -p"${DB_PASSWORD}" --silent 2>/dev/null; then
        echo "MariaDB is up."
        break
    fi
    echo "  attempt $i/30 - not ready yet, waiting 2s..."
    sleep 2
done


if [ ! -f /var/www/html/wp-config.php ]; then
    echo "First boot: installing WordPress..."

    wp core download --allow-root

    wp config create --allow-root \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="mariadb"

    wp core install --allow-root \
        --url="https://${DOMAIN_NAME}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}"

    wp user create --allow-root \
        "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=subscriber \
        --user_pass="${WP_USER_PASSWORD}"

    echo "WordPress installation complete."
else
    echo "WordPress already installed, skipping."
fi

    #---- bonus-------    
    wp config set WP_REDIS_HOST redis --allow-root
    wp config set WP_REDIS_PORT 6379 --allow-root --raw
    
    wp plugin install redis-cache --activate --allow-root
    if php -r 'try { exit((new Redis())->connect("redis", 6379, 2) ? 0 : 1); } catch (Exception $e) { exit(1); }' 2>/dev/null; then
        wp redis enable --allow-root
        echo "Redis cache enabled."
    else
        echo "Redis not reachable, skipping cache (site uses DB directly)."
    fi
    # --------

chown -R www-data:www-data /var/www/html

exec /usr/sbin/php-fpm8.2 -F
