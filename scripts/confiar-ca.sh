#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Lastro — instala a CA interna do appliance no repositório de
# confiança da máquina, para que o HTTPS local abra SEM AVISO em
# Chrome, Safari, Edge e Firefox.
#
# Por que isso existe: nenhuma autoridade pública emite certificado
# para "localhost". Ou o navegador confia na CA do appliance, ou o
# usuário vê um aviso — e, pior, com HSTS o aviso vira intransponível.
# É a mesma estratégia do mkcert.
#
# Uso:  sudo ./scripts/confiar-ca.sh          (instala)
#       sudo ./scripts/confiar-ca.sh --remover (desinstala)
# ════════════════════════════════════════════════════════════════════
set -u
cd "$(dirname "$0")/.."
CA_FILE="caddy/GRC-Hub-CA-local.crt"
CA_NOME="Lastro Local CA"
REMOVER=""; [ "${1:-}" = "--remover" ] && REMOVER=1

msg(){ printf '%s\n' "$*"; }
ok(){  printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn(){ printf '  \033[33m!\033[0m %s\n' "$*"; }
err(){ printf '  \033[31m✖\033[0m %s\n' "$*"; }

# ── 1. Extrai a CA raiz gerada pelo Caddy ───────────────────────────
extrair_ca(){
  for i in $(seq 1 30); do
    if docker exec sgsi_caddy sh -c 'test -f /data/caddy/pki/authorities/local/root.crt' 2>/dev/null; then
      docker exec sgsi_caddy sh -c 'cat /data/caddy/pki/authorities/local/root.crt' > "$CA_FILE" 2>/dev/null
      [ -s "$CA_FILE" ] && return 0
    fi
    [ $i -eq 1 ] && msg "  aguardando o Caddy gerar a CA interna…"
    sleep 2
  done
  return 1
}

if [ -z "$REMOVER" ]; then
  if ! extrair_ca; then
    err "não consegui obter a CA do container sgsi_caddy (a stack está no ar?)"
    exit 1
  fi
  ok "CA extraída: $CA_FILE"
fi

SO="$(uname -s)"

# ── 2. Repositório de confiança do SISTEMA ──────────────────────────
case "$SO" in
  Darwin)
    if [ -n "$REMOVER" ]; then
      security delete-certificate -c "Caddy Local Authority" /Library/Keychains/System.keychain 2>/dev/null \
        && ok "CA removida do Keychain do sistema" || warn "CA não encontrada no Keychain"
    else
      if security add-trusted-cert -d -r trustRoot \
           -k /Library/Keychains/System.keychain "$CA_FILE" 2>/dev/null; then
        ok "CA confiada no Keychain do sistema (Chrome, Safari e Edge)"
      else
        err "falha ao instalar no Keychain — rode com sudo"; exit 1
      fi
    fi
    ;;
  Linux)
    DEST=""
    if   [ -d /usr/local/share/ca-certificates ]; then DEST=/usr/local/share/ca-certificates/lastro-local-ca.crt; ATUALIZA="update-ca-certificates"
    elif [ -d /etc/pki/ca-trust/source/anchors ]; then DEST=/etc/pki/ca-trust/source/anchors/lastro-local-ca.crt; ATUALIZA="update-ca-trust extract"
    fi
    if [ -z "$DEST" ]; then err "distribuição não reconhecida (sem ca-certificates nem ca-trust)"; exit 1; fi
    if [ -n "$REMOVER" ]; then
      rm -f "$DEST" && $ATUALIZA >/dev/null 2>&1 && ok "CA removida do sistema"
    else
      cp "$CA_FILE" "$DEST" && $ATUALIZA >/dev/null 2>&1 \
        && ok "CA confiada no sistema (Chrome e Edge)" || { err "falha ao atualizar o repositório de CAs — rode com sudo"; exit 1; }
    fi
    ;;
  *) err "sistema não suportado por este script: $SO"; exit 1 ;;
esac

# ── 3. Firefox: usa repositório PRÓPRIO (NSS), não o do sistema ─────
# Em vez de mexer no banco NSS de cada perfil (frágil), usamos a política
# corporativa ImportEnterpriseRoots: o Firefox passa a confiar no
# repositório do SISTEMA — assim uma instalação só cobre todos os navegadores.
firefox_policy(){
  local dir="$1"
  [ -d "$(dirname "$dir")" ] || return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  local f="$dir/policies.json"
  if [ -n "$REMOVER" ]; then
    [ -f "$f" ] && grep -q ImportEnterpriseRoots "$f" 2>/dev/null && rm -f "$f" && return 0
    return 1
  fi
  # preserva outras políticas se o arquivo já existir
  if [ -f "$f" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$f" <<'PY' 2>/dev/null && return 0
import json,sys
p=sys.argv[1]
try: d=json.load(open(p))
except Exception: d={}
d.setdefault('policies',{}).setdefault('Certificates',{})['ImportEnterpriseRoots']=True
json.dump(d,open(p,'w'),indent=2)
PY
  fi
  printf '{\n  "policies": {\n    "Certificates": { "ImportEnterpriseRoots": true }\n  }\n}\n' > "$f" 2>/dev/null
}

FF_OK=""
case "$SO" in
  Darwin) firefox_policy "/Applications/Firefox.app/Contents/Resources/distribution" && FF_OK=1 ;;
  Linux)  for d in /etc/firefox/policies /usr/lib/firefox/distribution /usr/lib64/firefox/distribution \
                   /opt/firefox/distribution /snap/firefox/current/usr/lib/firefox/distribution; do
            firefox_policy "$d" && FF_OK=1 && break
          done ;;
esac
if [ -n "$REMOVER" ]; then
  [ -n "$FF_OK" ] && ok "política do Firefox removida" || warn "política do Firefox não encontrada"
else
  [ -n "$FF_OK" ] && ok "Firefox configurado para usar as CAs do sistema (ImportEnterpriseRoots)" \
                  || warn "Firefox não encontrado — se usar, importe $CA_FILE manualmente em Configurações → Certificados"
fi

# ── 4. Verificação real ─────────────────────────────────────────────
if [ -z "$REMOVER" ]; then
  msg ""
  if curl -sS --max-time 8 -o /dev/null https://localhost/ 2>/dev/null; then
    ok "HTTPS validado SEM --insecure: o certificado é confiável nesta máquina"
  else
    warn "a validação direta falhou (a stack pode ainda estar subindo)"
  fi
  msg ""
  msg "  Feche o navegador POR COMPLETO e abra: https://localhost"
fi
