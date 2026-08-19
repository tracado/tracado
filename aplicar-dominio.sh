#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# GRC Hub — aplica uma troca de domínio/certificado a partir do intent
# gravado pelo portal em /control/request.json. Executado pelo serviço
# 'configurator' (o único com acesso ao Docker).
#
# SEGURANÇA: o intent é apenas DADO (domínio, e-mail, modo, caminhos de
# cert), estritamente validado abaixo. A sequência de ações é FIXA — nada
# vindo do intent é executado como comando de shell.
#
# Uso (pelo sidecar):  aplicar-dominio.sh <request.json> <status.json>
# Uso manual (fallback, no host):  ./aplicar-dominio.sh <request.json>
# ════════════════════════════════════════════════════════════════════
set -u
REQ="${1:?informe o request.json}"
STATUS="${2:-/control/status.json}"
cd "$(dirname "$0")"
export PWD="$(pwd)"   # garante ${PWD} correto para o docker compose

j(){ jq -r "$1 // empty" "$REQ" 2>/dev/null; }
ID="$(j '.id')"
PORTAL="$(j '.portal_domain')"
AUTH="$(j '.auth_domain')"
MODE="$(j '.tls_mode')"
EMAIL="$(j '.acme_email')"
CERT="$(j '.cert_file')"
KEY="$(j '.key_file')"

st(){ # <state> <message> [log]
  printf '{"id":"%s","applied_id":"%s","state":"%s","message":%s,"log":%s,"ts":%s}\n' \
    "$ID" "$ID" "$1" \
    "$(printf '%s' "$2" | jq -Rs .)" \
    "$(printf '%s' "${3:-}" | jq -Rs .)" \
    "$(date +%s)" > "$STATUS"
}
fail(){ st "error" "$1" "${2:-}"; echo "ERRO: $1" >&2; exit 1; }

# ── validação (defesa em profundidade) ──────────────────────────────
RE='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$'
[ -n "$PORTAL" ] || fail "domínio do portal ausente"
echo "$PORTAL" | grep -Eq "$RE" || fail "domínio do portal inválido: $PORTAL"
[ -n "$AUTH" ] || AUTH="auth.$PORTAL"
echo "$AUTH" | grep -Eq "$RE" || fail "domínio de login inválido: $AUTH"
case "$MODE" in letsencrypt|upload|internal) ;; *) fail "modo TLS inválido: $MODE" ;; esac

st "applying" "Iniciando ($MODE) para $PORTAL…"

# ── 1. Caddyfile conforme o modo ────────────────────────────────────
case "$MODE" in
  letsencrypt)
    [ -n "$EMAIL" ] || EMAIL="admin@$PORTAL"
    echo "$EMAIL" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' || fail "e-mail ACME inválido"
    python3 - "$PORTAL" "$AUTH" "$EMAIL" <<'PY' || fail "falha ao gerar Caddyfile (letsencrypt)"
import sys; p,a,e=sys.argv[1:4]
t=open('caddy/Caddyfile.producao').read()
open('caddy/Caddyfile','w').write(t.replace('__PORTAL_DOMAIN__',p).replace('__AUTH_DOMAIN__',a).replace('__ACME_EMAIL__',e))
PY
    ;;
  internal)
    python3 - "$PORTAL" "$AUTH" <<'PY' || fail "falha ao gerar Caddyfile (interno)"
import sys; p,a=sys.argv[1:3]
t=open('caddy/Caddyfile.interno').read()
open('caddy/Caddyfile','w').write(t.replace('__PORTAL_DOMAIN__',p).replace('__AUTH_DOMAIN__',a))
PY
    ;;
  upload)
    [ -f "$CERT" ] || fail "certificado enviado não encontrado"
    [ -f "$KEY" ]  || fail "chave enviada não encontrada"
    grep -q 'BEGIN CERTIFICATE'      "$CERT" || fail "o arquivo de certificado não é PEM válido"
    grep -q 'BEGIN .*PRIVATE KEY'    "$KEY"  || fail "o arquivo de chave não é PEM válido"
    mkdir -p caddy/certs
    cp "$CERT" caddy/certs/portal.crt
    cp "$KEY"  caddy/certs/portal.key
    chmod 600 caddy/certs/portal.key
    python3 - "$PORTAL" "$AUTH" <<'PY' || fail "falha ao gerar Caddyfile (cert do cliente)"
import sys; p,a=sys.argv[1:3]
t=open('caddy/Caddyfile.certcliente').read()
open('caddy/Caddyfile','w').write(t.replace('__PORTAL_DOMAIN__',p).replace('__AUTH_DOMAIN__',a))
PY
    ;;
esac

# valida a sintaxe do Caddyfile ANTES de recriar (evita derrubar o gateway)
docker run --rm -e PORTAL_SHARED_SECRET=x -v "$PWD/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
  caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile >/tmp/caddyval.log 2>&1 \
  || fail "Caddyfile gerado é inválido" "$(cat /tmp/caddyval.log)"

# ── 2. .env: URLs públicas + cookie seguro ──────────────────────────
python3 - "$PORTAL" "$AUTH" <<'PY' || fail "falha ao atualizar .env"
import sys
portal,auth=sys.argv[1],sys.argv[2]
novos={'PORTAL_PUBLIC_URL':f'https://{portal}','PORTAL_PUBLIC_DOMAIN':portal,
       'KEYCLOAK_PUBLIC_URL':f'https://{auth}','OAUTH2_WHITELIST_DOMAINS':auth,
       'OAUTH2_COOKIE_SECURE':'true'}
lin=open('.env').read().splitlines(); vis=set(); out=[]
for l in lin:
    k=l.split('=',1)[0].strip() if '=' in l and not l.lstrip().startswith('#') else None
    if k in novos: out.append(f'{k}={novos[k]}'); vis.add(k)
    else: out.append(l)
for k,v in novos.items():
    if k not in vis: out.append(f'{k}={v}')
open('.env','w').write('\n'.join(out)+'\n')
PY

# ── 3. recria os serviços que dependem das novas URLs ───────────────
st "applying" "Recriando serviços (Caddy, login e portal de identidade)…"
docker compose up -d --force-recreate caddy oauth2-portal keycloak sgsi-portal >/tmp/apply.log 2>&1 \
  || fail "falha ao recriar os serviços" "$(tail -30 /tmp/apply.log)"

# ── 4. Keycloak: espera subir e atualiza as redirect URIs do client ─
st "applying" "Atualizando as URLs de retorno no Keycloak…"
KA="$(grep '^KEYCLOAK_ADMIN=' .env|cut -d= -f2-)"
KP="$(grep '^KEYCLOAK_ADMIN_PASSWORD=' .env|cut -d= -f2-)"
REALM="$(grep '^KEYCLOAK_REALM=' .env|cut -d= -f2-)"; REALM="${REALM:-sgsi}"
ok=""
for i in $(seq 1 40); do
  if docker exec sgsi_keycloak /opt/keycloak/bin/kcadm.sh config credentials \
       --server http://localhost:8080 --realm master --user "$KA" --password "$KP" >/dev/null 2>&1; then ok=1; break; fi
  sleep 3
done
[ -n "$ok" ] || fail "Keycloak não respondeu para atualizar as URLs (kcadm)"
CID="$(docker exec sgsi_keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" \
        -q clientId=sgsi-gateway --fields id --format csv 2>/dev/null | tr -d '"\r')"
[ -n "$CID" ] || fail "client sgsi-gateway não encontrado no realm $REALM"
docker exec sgsi_keycloak /opt/keycloak/bin/kcadm.sh update "clients/$CID" -r "$REALM" \
  -s "redirectUris=[\"https://$PORTAL/oauth2/callback\"]" \
  -s "webOrigins=[\"https://$PORTAL\"]" \
  -s "attributes={\"post.logout.redirect.uris\":\"https://$PORTAL/*\"}" >/dev/null 2>&1 \
  || fail "falha ao atualizar as redirect URIs no Keycloak"

LOG="Portal:   https://$PORTAL
Login:    https://$AUTH
Modo TLS: $MODE"
[ "$MODE" = letsencrypt ] && LOG="$LOG
DNS dos dois domínios deve apontar para este servidor; o cadeado aparece em ~30s."
[ "$MODE" = internal ]    && LOG="$LOG
Distribua a CA interna (caddy/GRC-Hub-CA-local.crt) nas máquinas do cliente."
st "ok" "Domínio aplicado: https://$PORTAL" "$LOG"
echo "OK: $PORTAL ($MODE)"
