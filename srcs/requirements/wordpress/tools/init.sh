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

DB_PASSWORD="$(cat /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(cat /run/secrets/credentials)"
WP_USER_PASSWORD="$(cat /run/secrets/wp_user_password)"

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
        --role=editor \
        --user_pass="${WP_USER_PASSWORD}"

    echo "WordPress installation complete."
else
    echo "WordPress already installed, skipping."
fi

#---- bonus-------    
if getent hosts redis >/dev/null 2>&1; then
    wp config set WP_REDIS_HOST redis --allow-root || true
    wp config set WP_REDIS_PORT 6379 --raw --allow-root || true
    wp plugin is-installed redis-cache --allow-root \
        || wp plugin install redis-cache --activate --allow-root || true
    if php -r 'try { exit((new Redis())->connect("redis",6379,2)?0:1); } catch (Throwable $e) { exit(1); }' 2>/dev/null; then
        wp redis enable --allow-root || true
        echo "Redis cache enabled."
    fi
fi

chown -R www-data:www-data /var/www/html

exec /usr/sbin/php-fpm8.2 -F
