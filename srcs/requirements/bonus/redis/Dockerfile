# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Dockerfile                                         :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/31 12:06:58 by ghenriqu          #+#    #+#              #
#    Updated: 2026/08/01 16:06:24 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #


FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends redis-server && \
    rm -rf /var/lib/apt/lists/*

COPY conf/redis.conf /etc/redis/redis.conf
COPY tools/init.sh   /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

EXPOSE 6379

ENTRYPOINT ["/usr/local/bin/init.sh"]