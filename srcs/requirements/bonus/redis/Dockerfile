# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Dockerfile                                         :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/28 00:00:00 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/28 00:00:00 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends redis-server && \
    rm -rf /var/lib/apt/lists/*

COPY conf/redis.conf /etc/redis/redis.conf
COPY tools/init.sh   /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

# Documental: a porta nunca é publicada no host, só é alcançável na rede interna.
EXPOSE 6379

ENTRYPOINT ["/usr/local/bin/init.sh"]