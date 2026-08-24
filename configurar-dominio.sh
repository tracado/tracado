#!/usr/bin/env bash
set -euo pipefail

# ════════════════════════════════════════════════════════════════════
# Traçado — coloca o appliance no DOMÍNIO PRÓPRIO do cliente, com
# HTTPS automático (Let's Encrypt via Caddy).
#
# Uso:
#   ./configurar-dominio.sh grc.cliente.com.br [auth.grc.cliente.com.br] [email-acme@cliente.com.br]
#
#   1º argumento  domínio do portal (obrigatório)
#   2º argumento  domínio do Keycloak/login (padrão: auth.<domínio do portal>)
#   3º argumento  e-mail para os certificados Let's Encrypt (padrão: admin@<domínio>)
#
# Pré-requisitos NO CLIENTE:
#   • DNS: registros A/AAAA dos DOIS domínios apontando para este servidor
#   • Firewall: portas 80 e 443 abertas para a internet (emissão do certificado)
#
# O script é idempotente: rode de novo para trocar de domínio.
# Para voltar ao modo localhost: remova docker-compose.override.yml,
# rode ./install.sh local e ajuste o .env de volta.
# ════════════════════════════════════════════════════════════════════
cd "$(dirname "$0")"

PORTAL_DOMAIN="${1:-}"
AUTH_DOMAIN="${2:-}"
ACME_EMAIL="${3:-}"

if [ -z "$PORTAL_DOMAIN" ]; then
  echo "Uso: ./configurar-dominio.sh grc.cliente.com.br [auth.grc.cliente.com.br] [email@cliente.com.br]"
  exit 1
fi
case "$PORTAL_DOMAIN" in
  http*://*|*/*|*:* ) echo "✖ Informe apenas o domínio, sem https:// nem porta (ex.: grc.cliente.com.br)"; exit 1;;
esac
AUTH_DOMAIN="${AUTH_DOMAIN:-auth.${PORTAL_DOMAIN}}"
ACME_EMAIL="${ACME_EMAIL:-admin@${PORTAL_DOMAIN}}"

command -v python3 >/dev/null 2>&1 || { echo "✖ python3 não encontrado."; exit 1; }
[ -f .env ] || { echo "✖ .env não encontrado — rode primeiro ./install.sh"; exit 1; }
if docker compose version >/dev/null 2>&1; then DC="docker compose";
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose";
else echo "✖ Docker Compose não encontrado."; exit 1; fi

echo "═══════════════════════════════════════════════════"
echo " Traçado → domínio próprio do cliente"
echo "   Portal:   https://${PORTAL_DOMAIN}"
echo "   Login:    https://${AUTH_DOMAIN}"
echo "   ACME:     ${ACME_EMAIL}"
echo "═══════════════════════════════════════════════════"

# ── Analista IA: mantém o que já roda, ou pergunta ───────────────────
# (quando chamado pelo install.sh, GRC_INSTALL=1 evita perguntar de novo)
PULL_IA=""
if [ -n "${COMPOSE_PROFILES:-}" ]; then
  echo "✓ Profile '${COMPOSE_PROFILES}' herdado do instalador"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^sgsi_ollama$'; then
  export COMPOSE_PROFILES=ia
  echo "✓ Analista IA em execução — profile 'ia' mantido"
elif [ -t 0 ] && [ -z "${GRC_INSTALL:-}" ]; then
  printf "Ativar o Analista IA com LLM local? Baixa ~1GB na 1ª vez [s/N]: "
  read -r R || true
  case "${R:-}" in [sSyY]*) export COMPOSE_PROFILES=ia; PULL_IA="1" ;; esac
fi

# Aviso preventivo de DNS (best-effort; não bloqueia ambientes sem 'getent')
for d in "$PORTAL_DOMAIN" "$AUTH_DOMAIN"; do
  if command -v getent >/dev/null 2>&1 && ! getent hosts "$d" >/dev/null 2>&1; then
    echo "⚠ DNS de ${d} ainda não resolve — o certificado só será emitido depois que o registro A apontar para este servidor."
  fi
done

# ── 1. .env: URLs públicas + cookie seguro (HTTPS) ───────────────────
python3 - "$PORTAL_DOMAIN" "$AUTH_DOMAIN" <<'PYEOF'
import sys
portal, auth = sys.argv[1], sys.argv[2]
novos = {
    'PORTAL_PUBLIC_URL':       f'https://{portal}',
    'PORTAL_PUBLIC_DOMAIN':    portal,
    'KEYCLOAK_PUBLIC_URL':     f'https://{auth}',
    'OAUTH2_WHITELIST_DOMAINS': auth,
    'OAUTH2_COOKIE_SECURE':    'true',
}
linhas = open('.env').read().splitlines()
vistos = set()
saida = []
for l in linhas:
    chave = l.split('=', 1)[0].strip() if '=' in l and not l.lstrip().startswith('#') else None
    if chave in novos:
        saida.append(f'{chave}={novos[chave]}')
        vistos.add(chave)
    else:
        saida.append(l)
for k, v in novos.items():
    if k not in vistos:
        saida.append(f'{k}={v}')
open('.env', 'w').write('\n'.join(saida) + '\n')
print('✓ .env atualizado (URLs públicas + cookie seguro)')
PYEOF

# ── 2. Caddyfile de produção (HTTPS automático) ──────────────────────
python3 - "$PORTAL_DOMAIN" "$AUTH_DOMAIN" "$ACME_EMAIL" <<'PYEOF'
import sys
portal, auth, email = sys.argv[1], sys.argv[2], sys.argv[3]
tpl = open('caddy/Caddyfile.producao').read()
tpl = tpl.replace('__PORTAL_DOMAIN__', portal).replace('__AUTH_DOMAIN__', auth).replace('__ACME_EMAIL__', email)
open('caddy/Caddyfile', 'w').write(tpl)
print('✓ caddy/Caddyfile de produção gerado')
PYEOF

# ── 3. Override do compose: expõe 80/443 no host ─────────────────────
if [ ! -f docker-compose.override.yml ] || ! grep -q "TRACADO-PRODUCAO" docker-compose.override.yml; then
  cat > docker-compose.override.yml <<'YAML'
# TRACADO-PRODUCAO — gerado por configurar-dominio.sh
# Expõe HTTP/HTTPS no host para o domínio do cliente (Let's Encrypt usa a 80).
services:
  caddy:
    ports:
      - "80:80"
      - "443:443"
YAML
  echo "✓ docker-compose.override.yml criado (portas 80/443)"
else
  echo "✓ docker-compose.override.yml já existente (mantido)"
fi

# ── 4. Realm do Keycloak: re-renderiza para instalações/importações novas ──
python3 - <<'PYEOF'
env = {}
for l in open('.env'):
    if '=' in l and not l.lstrip().startswith('#'):
        k, v = l.split('=', 1); env[k.strip()] = v.strip()
tpl = open('keycloak/realm-sgsi.template.json').read()
tpl = (tpl.replace('${KEYCLOAK_CLIENT_SECRET}', env.get('KEYCLOAK_CLIENT_SECRET', ''))
          .replace('${MASTER_PASSWORD}',        env.get('MASTER_PASSWORD', ''))
          .replace('${PORTAL_PUBLIC_URL}',      env.get('PORTAL_PUBLIC_URL', 'http://localhost:8080'))
          .replace('${MASTER_EMAIL}',           env.get('MASTER_EMAIL', 'admin@sgsi.local')))
open('keycloak/realm-sgsi.json', 'w').write(tpl)
print('✓ keycloak/realm-sgsi.json re-renderizado')
PYEOF

# ── 5. Sobe a stack com a nova configuração ──────────────────────────
echo "Recriando os serviços com o novo domínio..."
$DC up -d
sleep 5

# Analista IA recém-ativado: baixa o modelo (idempotente)
if [ -n "$PULL_IA" ]; then
  MODEL="$(grep '^OLLAMA_MODEL=' .env 2>/dev/null | cut -d= -f2- || true)"
  MODEL="${MODEL:-qwen2.5:1.5b}"
  echo "Analista IA: verificando modelo ${MODEL}..."
  if $DC exec -T ollama ollama list 2>/dev/null | grep -q "${MODEL%%:*}"; then
    echo "Analista IA: modelo ${MODEL} já disponível. ✓"
  else
    echo "Analista IA: baixando ${MODEL} (~1GB, só na primeira vez)..."
    $DC exec -T ollama ollama pull "$MODEL"
  fi
fi

# ── 6. Realm VIVO: atualiza as redirect URIs do client (import é IGNORE_EXISTING) ──
KC_ADMIN="$(grep '^KEYCLOAK_ADMIN=' .env | cut -d= -f2-)"
KC_PASS="$(grep '^KEYCLOAK_ADMIN_PASSWORD=' .env | cut -d= -f2-)"
REALM="$(grep '^KEYCLOAK_REALM=' .env | cut -d= -f2-)"; REALM="${REALM:-sgsi}"
echo "Atualizando as redirect URIs no Keycloak (realm ${REALM})..."
if $DC exec -T keycloak /opt/keycloak/bin/kcadm.sh config credentials \
     --server http://localhost:8080 --realm master \
     --user "$KC_ADMIN" --password "$KC_PASS" >/dev/null 2>&1; then
  CID="$($DC exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" \
         -q clientId=sgsi-gateway --fields id --format csv --noquotes 2>/dev/null | head -1 | tr -d '\r')"
  if [ -n "$CID" ]; then
    $DC exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$CID" -r "$REALM" \
      -s "redirectUris=[\"https://${PORTAL_DOMAIN}/oauth2/callback\"]" \
      -s "webOrigins=[\"https://${PORTAL_DOMAIN}\"]" \
      && echo "✓ Client sgsi-gateway atualizado: https://${PORTAL_DOMAIN}/oauth2/callback"
  else
    echo "⚠ Client sgsi-gateway não encontrado no realm ${REALM} — atualize as Redirect URIs manualmente no console."
  fi
else
  echo "⚠ Não foi possível autenticar no kcadm (Keycloak ainda subindo?)."
  echo "  Rode novamente: ./configurar-dominio.sh ${PORTAL_DOMAIN} ${AUTH_DOMAIN}"
fi

echo
echo "═══════════════════════════════════════════════════"
echo " ✓ Domínio configurado!"
echo "   Portal:   https://${PORTAL_DOMAIN}"
echo "   Keycloak: https://${AUTH_DOMAIN}  (console: /admin)"
echo
echo " Checklist final no cliente:"
echo "   1. DNS: ${PORTAL_DOMAIN} e ${AUTH_DOMAIN} → IP deste servidor"
echo "   2. Firewall: portas 80 e 443 abertas (o certificado é emitido na 1ª visita)"
echo "   3. Acesse https://${PORTAL_DOMAIN} — o cadeado deve aparecer em ~30s"
echo " Os acessos locais :8080/:8086 continuam funcionando para contingência."
echo "═══════════════════════════════════════════════════"
