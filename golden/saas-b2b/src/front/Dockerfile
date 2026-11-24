# Front of the SaaS B2B golden repo (spec 001, step 4). Build context:
# src/front/. Base images pinned by tag and digest (S01), both from Docker
# Hub, which dates its tags: Renovate counts the 7 days (research RS-05 and
# RS-18).
# - node 26.13.1, Active LTS, Alpine variant: build and tests only, never
#   deployed;
# - nginx 1.30.7, stable, alpine-slim variant: serves the built files under
#   the non-root user of the image, UID 101, on port 8080, as the restricted
#   profile wants (ADR-012, condition 9).
#
# Stages, all run by tests/unit/u02-front.sh except runtime alone:
# - deps: npm ci, locked to package-lock.json, no install script (.npmrc);
# - sources: deps and the sources;
# - build: type check, then the production build into dist/;
# - unit: U02 with Vitest, in the build image (research RS-06);
# - runtime: the image of the front;
# - serve-check: nginx -t under the non-root user, and a built page that
#   loads its code from files only, as the Content-Security-Policy of
#   nginx.conf requires;
# - test: needs unit and serve-check, keeps nothing;
# - lock, then lock-files: package-lock.json resolved anew (--update-locks).

FROM node:26.13.1-alpine@sha256:6bd9ab43c0ec0190ca7b2d193906cb8b7edf6e7f4afa43ddeccd6452710bffb5 AS node
WORKDIR /app
COPY package.json .npmrc ./

# Each package resolved anew must have been published more than 7 days ago
# (principle VI); packages already in package-lock.json stay as they are.
FROM node AS lock
COPY package*.json ./
RUN npm install --package-lock-only --min-release-age=7

FROM scratch AS lock-files
COPY --from=lock /app/package-lock.json /

# npm ci installs exactly the tree of package-lock.json, or fails if
# package.json asks for another one (research RS-18).
FROM node AS deps
COPY package-lock.json ./
RUN npm ci

FROM deps AS sources
COPY . .

FROM sources AS build
RUN npm run build

FROM sources AS unit
RUN npm test

FROM nginx:1.30.7-alpine-slim@sha256:8c950211a641ec5b23f265450517001f6bcca533666120ebe36cb4cff3d00a55 AS runtime
# No configuration script at start (templates, IPv6 listen, resolvers), no
# default site: nginx.conf below is the whole configuration.
RUN rm -f /docker-entrypoint.d/* /etc/nginx/conf.d/default.conf \
    && rm -rf /usr/share/nginx/html/*
COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/dist/ /usr/share/nginx/html/
# The nginx user and group of the image, by number, so that the restricted
# profile can check runAsNonRoot (research RS-05).
USER 101:101
EXPOSE 8080

FROM runtime AS serve-check
RUN nginx -t \
    && if grep -o '<script[^>]*>' /usr/share/nginx/html/index.html | grep -v -q ' src='; then \
         echo "index.html holds an inline script, which the Content-Security-Policy of nginx.conf blocks." >&2; exit 1; \
       fi \
    && if grep -q '<style' /usr/share/nginx/html/index.html; then \
         echo "index.html holds an inline style, which the Content-Security-Policy of nginx.conf blocks." >&2; exit 1; \
       fi

FROM scratch AS test
COPY --from=unit /app/package.json /unit/
COPY --from=serve-check /etc/nginx/nginx.conf /serve-check/
