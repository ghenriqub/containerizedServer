# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Dockerfile                                         :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/31 12:07:11 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/31 12:07:13 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

FROM debian:bookworm

ARG ADMINER_VERSION=5.5.1
ARG ADMINER_SHA256=6e45aa92c310e11033adfc09ff62a484bd14b59c86e4e30ca0ff567af4d0c278

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.2-fpm php8.2-mysql \
        ca-certificates curl && \
    mkdir -p /var/www/adminer && \
    curl -fsSL -o /var/www/adminer/index.php \
        "https://github.com/vrana/adminer/releases/download/v${ADMINER_VERSION}/adminer-${ADMINER_VERSION}-mysql.php" && \
    echo "${ADMINER_SHA256}  /var/www/adminer/index.php" | sha256sum -c - && \
    chown www-data:www-data /var/www/adminer/index.php && \
    chmod 444 /var/www/adminer/index.php && \
    apt-get purge -y --auto-remove curl && \
    rm -rf /var/lib/apt/lists/*

COPY conf/www.conf       /etc/php/8.2/fpm/pool.d/www.conf
COPY conf/99-adminer.ini /etc/php/8.2/fpm/conf.d/99-adminer.ini
COPY tools/init.sh       /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/init.sh"]
