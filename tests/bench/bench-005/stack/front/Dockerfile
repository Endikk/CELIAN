# BENCH-005 test front: static files served by nginx on port 8080.
# Base image pinned by digest (read on 2026-11-19).
FROM nginx:1.30.7-alpine@sha256:bef154735288bc38d99fac41ae63730684bcc661503673a04a0f9bc526ba8598
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY html/ /usr/share/nginx/html/
