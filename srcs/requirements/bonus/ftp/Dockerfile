# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Dockerfile                                         :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/31 14:16:21 by ghenriqu          #+#    #+#              #
#    Updated: 2026/08/01 15:25:57 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

FROM debian:bookworm

ARG DOMAIN_NAME
ARG FTP_USER=ftpuser

RUN apt-get update && \
    apt-get install -y --no-install-recommends vsftpd openssl && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/vsftpd/ssl && \
    openssl req -x509 -nodes \
        -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/vsftpd/ssl/vsftpd.key \
        -out /etc/vsftpd/ssl/vsftpd.crt \
        -subj "/C=PT/ST=Porto/L=Porto/O=42Porto/CN=${DOMAIN_NAME}" && \
    chmod 600 /etc/vsftpd/ssl/vsftpd.key

RUN mkdir -p /var/www && \
    chmod 755 /var/www

RUN useradd \
        --home-dir /var/www \
        --no-create-home \
        --gid www-data \
        --shell /usr/sbin/nologin \
        "${FTP_USER}" && \
    chown root:www-data /var/www

RUN grep -qxF /usr/sbin/nologin /etc/shells || echo /usr/sbin/nologin >> /etc/shells

COPY conf/vsftpd.conf /etc/vsftpd/vsftpd.conf.template
COPY tools/init.sh    /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

EXPOSE 21 30000-30009

ENTRYPOINT ["/usr/local/bin/init.sh"]
