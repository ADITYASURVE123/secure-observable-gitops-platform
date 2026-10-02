# syntax=docker/dockerfile:1.7
FROM node:22.12.0-alpine3.21 AS build
WORKDIR /src
ARG BUILD_VERSION=dev
ENV BUILD_VERSION=$BUILD_VERSION
COPY package.json build.mjs ./
COPY src ./src
RUN node build.mjs

# nginx-unprivileged runs as UID 101 and listens on 8080, so no capabilities are needed.
FROM nginxinc/nginx-unprivileged:1.27.3-alpine3.20 AS runtime
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/dist /usr/share/nginx/html
USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
