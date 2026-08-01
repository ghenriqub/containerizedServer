#!/bin/bash

# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    init.sh                                            :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/31 14:19:46 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/31 14:19:56 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

set -eu

TEMPLATE="/etc/vsftpd/vsftpd.conf.template"
RUNTIME_CONF="/run/vsftpd/vsftpd.conf"
SECRET_FILE="/run/secrets/ftp_password"

: "${FTP_USER:?FTP_USER not set (define it in srcs/.env)}"
: "${FTP_PASV_ADDRESS:=127.0.0.1}"

if [ ! -s "${SECRET_FILE}" ]; then
    echo "ERROR: ${SECRET_FILE} missing or empty." >&2
    exit 1
fi

echo "${FTP_USER}:$(cat "${SECRET_FILE}")" | chpasswd

mkdir -p /var/run/vsftpd/empty
chmod 555 /var/run/vsftpd/empty

mkdir -p /var/www/html
chown www-data:www-data /var/www/html
chmod 775 /var/www/html

mkdir -p /run/vsftpd
cp "${TEMPLATE}" "${RUNTIME_CONF}"
printf 'pasv_address=%s\n' "${FTP_PASV_ADDRESS}" >> "${RUNTIME_CONF}"
chmod 600 "${RUNTIME_CONF}"

echo "[ftp] user=${FTP_USER} chroot=/var/www pasv=${FTP_PASV_ADDRESS}:30000-30009 (FTPS required)"

exec vsftpd "${RUNTIME_CONF}"
