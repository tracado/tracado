#!/usr/bin/env bash
set -euo pipefail
[ -f .env ] || cp .env.example .env
for key in POSTGRES_PASSWORD KEYCLOAK_ADMIN_PASSWORD KEYCLOAK_CLIENT_SECRET FLASK_SECRET_KEY PORTAL_SHARED_SECRET; do ./scripts/set-env.sh "$key" "$(openssl rand -hex 32)"; done
if grep -q '^MASTER_PASSWORD=CHANGE_ME' .env; then ./scripts/set-env.sh MASTER_PASSWORD "Sgsi@$(openssl rand -hex 6)!"; fi
if grep -q '^OAUTH2_PROXY_COOKIE_SECRET=CHANGE_ME' .env; then ./scripts/set-env.sh OAUTH2_PROXY_COOKIE_SECRET "$(openssl rand -base64 32 | tr -- '+/' '-_' | tr -d '=')"; fi
