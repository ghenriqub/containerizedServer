# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Dockerfile                                         :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: ghenriqu <ghenriqu@student.42porto.com>    +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2026/07/31 12:28:20 by ghenriqu          #+#    #+#              #
#    Updated: 2026/07/31 12:35:52 by ghenriqu         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

FROM debian:bookworm AS builder

ARG UPTIME_KUMA_VERSION=2.4.0

ARG UPTIME_KUMA_SHA256=sha256:015ebb4df74b72bd8c303bdc41b71e2de8bdc72862ddc2d65db69a92316df835

ARG NODE_MAJOR=22

ENV PUPPETEER_SKIP_DOWNLOAD=true \
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    NODE_ENV=development

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg \
        build-essential python3 && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN curl -fsSL -o kuma.tar.gz \
        "https://github.com/louislam/uptime-kuma/releases/download/2.4.0/dist.tar.gz" && \
    echo "${UPTIME_KUMA_SHA256}  kuma.tar.gz" | sha256sum -c - && \
    tar -xzf kuma.tar.gz --strip-components=1 && \
    rm kuma.tar.gz

RUN NODE_OPTIONS=--max-old-space-size=2048 npm ci && \
    NODE_OPTIONS=--max-old-space-size=2048 npm run build && \
    npm prune --omit=dev && \
    npm cache clean --force && \
    rm -rf /root/.npm /build/.git

FROM debian:bookworm

ARG NODE_MAJOR=22

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg tzdata iputils-ping && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get purge -y --auto-remove curl gnupg && \
    rm -rf /var/lib/apt/lists/*

RUN useradd --system --create-home --home-dir /app --shell /usr/sbin/nologin kuma

WORKDIR /app

COPY --from=builder --chown=kuma:kuma /build /app
COPY tools/init.sh /usr/local/bin/init.sh
RUN chmod +x /usr/local/bin/init.sh

ENV NODE_ENV=production \
    DATA_DIR=/app/data/ \
    UPTIME_KUMA_HOST=0.0.0.0 \
    UPTIME_KUMA_PORT=3001

EXPOSE 3001

ENTRYPOINT ["/usr/local/bin/init.sh"]
