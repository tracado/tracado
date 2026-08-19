#!/usr/bin/env bash
source .env
docker compose ps
for url in http://localhost:8080 http://localhost:8086; do printf "%s -> " "$url"; curl -L -s -o /dev/null -w "%{http_code}
" "$url" || true; done
