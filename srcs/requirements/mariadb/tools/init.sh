#!/bin/bash

# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    init.sh                                            :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/22 22:52:31 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/22 22:53:07 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

set -eu

DATADIR="/var/lib/mysql"

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"
DB_PASSWORD="$(cat /run/secrets/db_password)"

if [ ! -d "${DATADIR}/mysql" ]; then
    echo "[mariadb] Empty datadir: installing system tables..."
    chown -R mysql:mysql "${DATADIR}"
    mariadb-install-db --user=mysql --datadir="${DATADIR}" --skip-test-db >/dev/null
    echo "[mariadb] System tables installed."
fi

INIT_SQL="/tmp/init.sql"
rm -f "${INIT_SQL}"
cat > "${INIT_SQL}" <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';

CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;

CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';

EOF

chown mysql:mysql "${INIT_SQL}"
chmod 600 "${INIT_SQL}"

echo "[mariadb] Starting mariadbd (PID 1)..."
exec mariadbd --user=mysql --init-file="${INIT_SQL}"
