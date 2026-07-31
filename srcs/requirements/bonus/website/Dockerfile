# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Dockerfile                                         :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/31 11:31:29 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/31 12:06:17 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/nginx /var/www/website && \
    chown -R www-data:www-data /run/nginx /var/lib/nginx

COPY conf/nginx.conf /etc/nginx/nginx.conf
COPY tools/init.sh   /usr/local/bin/init.sh
COPY site/           /var/www/website/

RUN chmod +x /usr/local/bin/init.sh && \
    chmod -R a-w /var/www/website

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/init.sh"]