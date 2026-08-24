#!/usr/bin/env bash
set -euo pipefail

# ════════════════════════════════════════════════════════════════════
# Traçado — instalador para Linux (Ubuntu/Debian/RHEL) e macOS.
# Windows: use o install.bat (duplo clique).
#
# Basta rodar ./install.sh SEM parâmetros: o instalador pergunta se é
# local ou produção (domínio do cliente), se quer o Analista IA e se
# é reinstalação. Parâmetros continuam valendo para automação:
#
# Uso: ./install.sh [local] [--reset] [--ia]
#   --reset  apaga os volumes (banco zerado, recarrega demo + migrações)
#   --ia     sobe também o Analista IA (Ollama) e baixa o modelo
# ════════════════════════════════════════════════════════════════════
MODE="local"; RESET=""; IA=""
PROD_DOMAIN=""; PROD_AUTH=""; PROD_EMAIL=""
for arg in "$@"; do
  case "$arg" in
    --reset) RESET="--reset" ;;
    --ia)    IA="1" ;;
    *)       MODE="$arg" ;;
  esac
done

cd "$(dirname "$0")"

# ── Modo interativo: sem parâmetros e num terminal, o instalador pergunta ──
if [ $# -eq 0 ] && [ -t 0 ]; then
  echo "═══════════════════════════════════════════"
  echo "   Traçado — Instalação guiada"
  echo "═══════════════════════════════════════════"
  echo "Onde o Traçado vai rodar?"
  echo "  [1] Local / testes  (http://localhost:8080)"
  echo "  [2] Produção com o domínio do cliente (HTTPS automático)"
  printf "Escolha [1]: "; read -r R || true
  if [ "${R:-1}" = "2" ]; then
    printf "Domínio do portal (ex.: grc.cliente.com.br): "; read -r PROD_DOMAIN || true
    [ -n "$PROD_DOMAIN" ] || { echo "✖ O domínio é obrigatório no modo produção."; exit 1; }
    printf "Domínio do login/Keycloak [auth.%s]: " "$PROD_DOMAIN"; read -r PROD_AUTH || true
    PROD_AUTH="${PROD_AUTH:-auth.$PROD_DOMAIN}"
    printf "E-mail para o certificado Let's Encrypt [admin@%s]: " "$PROD_DOMAIN"; read -r PROD_EMAIL || true
    PROD_EMAIL="${PROD_EMAIL:-admin@$PROD_DOMAIN}"
    echo "→ Lembrete: DNS de ${PROD_DOMAIN} e ${PROD_AUTH} apontando para este servidor + portas 80/443 abertas."
  fi
  printf "Ativar o Analista IA com LLM local? Baixa ~1GB na 1ª vez [s/N]: "; read -r R || true
  case "${R:-}" in [sSyY]*) IA="1" ;; esac
  printf "Reinstalar do zero (APAGA o banco de dados)? [s/N]: "; read -r R || true
  case "${R:-}" in [sSyY]*) RESET="--reset" ;; esac
  echo
fi

# ── Pré-requisitos: instala o Docker quando ausente ──────────────────
# Linux: automatizável de ponta a ponta (script oficial da Docker).
# macOS: precisa do Docker Desktop; instalamos via Homebrew quando houver,
#        senão orientamos o download (a 1ª abertura é manual, por design da Apple).
if ! command -v docker >/dev/null 2>&1; then
  SO="$(uname -s)"
  echo "Docker não encontrado — instalando…"
  if [ "$SO" = "Linux" ]; then
    if [ "$(id -u)" -ne 0 ] && ! command -v sudo >/dev/null 2>&1; then
      echo "✖ Preciso de root (ou sudo) para instalar o Docker."; exit 1
    fi
    SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
    curl -fsSL https://get.docker.com | $SUDO sh || {
      echo "✖ Falha ao instalar o Docker. Veja https://docs.docker.com/engine/install/"; exit 1; }
    $SUDO systemctl enable --now docker >/dev/null 2>&1 || $SUDO service docker start >/dev/null 2>&1 || true
    # permite usar o docker sem sudo nas próximas vezes
    [ -n "$SUDO" ] && $SUDO usermod -aG docker "$USER" 2>/dev/null || true
    echo "✓ Docker Engine instalado."
  elif [ "$SO" = "Darwin" ]; then
    if command -v brew >/dev/null 2>&1; then
      echo "  instalando o Docker Desktop via Homebrew…"
      brew install --cask docker || { echo "✖ Falha no brew. Baixe em https://www.docker.com/products/docker-desktop/"; exit 1; }
      open -a Docker 2>/dev/null || true
      echo "  aguardando o Docker Desktop iniciar…"
    else
      echo "✖ Docker não encontrado e o Homebrew não está disponível."
      echo "  Baixe o Docker Desktop: https://www.docker.com/products/docker-desktop/"
      echo "  Abra-o uma vez e rode este instalador novamente."; exit 1
    fi
  else
    echo "✖ Sistema não suportado automaticamente: $SO"; exit 1
  fi
fi
# espera o daemon responder (no macOS o Desktop demora a subir)
if ! docker info >/dev/null 2>&1; then
  echo "  aguardando o daemon do Docker…"
  for _i in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 2; done
fi
docker info >/dev/null 2>&1 || {
  echo "✖ O daemon do Docker não respondeu."
  echo "  Linux: sudo systemctl start docker  |  e adicione-se ao grupo: sudo usermod -aG docker \$USER"
  echo "  macOS: abra o Docker Desktop e rode novamente."; exit 1; }

# docker compose (plugin v2) com fallback para docker-compose (legado)
if docker compose version >/dev/null 2>&1; then DC="docker compose";
elif command -v docker-compose >/dev/null 2>&1; then DC="docker-compose";
else
  echo "✖ Docker Compose não encontrado. Instale o plugin: https://docs.docker.com/compose/install/"; exit 1;
fi

command -v python3 >/dev/null 2>&1 || {
  echo "✖ python3 não encontrado (necessário para preparar a configuração)."
  echo "  Ubuntu/Debian: sudo apt-get install -y python3"; exit 1; }
command -v openssl >/dev/null 2>&1 || {
  echo "✖ openssl não encontrado (necessário para gerar as senhas)."
  echo "  Ubuntu/Debian: sudo apt-get install -y openssl"; exit 1; }

# ── Configuração ─────────────────────────────────────────────────────
[ -f .env ] || cp .env.example .env
chmod +x scripts/*.sh *.sh 2>/dev/null || true
if grep -q CHANGE_ME .env; then ./generate-secrets.sh; fi
./scripts/render-keycloak-realm.sh
# preserva o Caddyfile de produção (domínio próprio via ./configurar-dominio.sh)
if [ -f caddy/Caddyfile ] && grep -q "GRC-HUB-PRODUCAO" caddy/Caddyfile; then
  echo "Caddyfile de produção detectado — mantido (para voltar ao localhost, apague caddy/Caddyfile)."
else
  cp caddy/Caddyfile.local caddy/Caddyfile
fi

# Profile da IA (opcional)
if [ "$IA" = "1" ]; then export COMPOSE_PROFILES=ia; fi

# ── Subida ───────────────────────────────────────────────────────────
if [ "$RESET" = "--reset" ]; then $DC down -v || true; fi
$DC pull
docker run --rm -v "$PWD/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2-alpine caddy validate --config /etc/caddy/Caddyfile
# Sem --build: o cliente recebe a IMAGEM publicada e assinada, não o código.
# Para desenvolver a partir do fonte, use docker-compose.dev.yml.
$DC up -d
sleep 15

# Analista IA: tier automático por RAM + download dos modelos (idempotente)
if [ "$IA" = "1" ]; then
  # ── Tier por RAM disponível ao Docker (respeita OLLAMA_MODEL já definido) ──
  MEM_BYTES="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
  MEM_GB=$(( MEM_BYTES / 1073741824 ))
  # Modelo de VISÃO desativado por padrão: em appliance vendido, o vl:3b/7b soma
  # ~3–5GB de RAM ao lado do LLM e entrega descrição genérica de pouco valor.
  # Fotos sem texto (catraca, sala-cofre) são correlacionadas pela DESCRIÇÃO que
  # o usuário informa — determinístico, instantâneo, 0 GB extra.
  if ! grep -q '^OLLAMA_MODEL=' .env; then
    if   [ "$MEM_GB" -ge 8 ]; then LLM="qwen2.5:7b";   TIER="completo"
    elif [ "$MEM_GB" -ge 6 ]; then LLM="qwen2.5:3b";   TIER="intermediário"
    else                           LLM="qwen2.5:1.5b"; TIER="básico"; fi
    echo "Analista IA: ${MEM_GB}GB de RAM no Docker → tier ${TIER} (LLM ${LLM})"
    ./scripts/set-env.sh OLLAMA_MODEL "$LLM"
    # re-sobe o portal com o tier escolhido no ambiente
    $DC up -d sgsi-portal >/dev/null 2>&1 || true
  fi
  MODEL="$(grep '^OLLAMA_MODEL=' .env 2>/dev/null | cut -d= -f2- || true)"; MODEL="${MODEL:-qwen2.5:1.5b}"
  EMBED="$(grep '^EMBED_MODEL=' .env 2>/dev/null | cut -d= -f2- || true)";  EMBED="${EMBED:-nomic-embed-text}"
  VISM="$(grep '^VISION_MODEL=' .env 2>/dev/null | cut -d= -f2- || true)"
  for M in "$MODEL" "$EMBED" $VISM; do
    [ -n "$M" ] || continue
    echo "Analista IA: verificando modelo ${M}..."
    if $DC exec -T ollama ollama list 2>/dev/null | grep -q "${M%%:*}"; then
      echo "Analista IA: modelo ${M} já disponível. ✓"
    else
      echo "Analista IA: baixando ${M} (só na primeira vez)..."
      $DC exec -T ollama ollama pull "$M"
    fi
  done
fi

# Produção: aplica o domínio do cliente (Caddyfile HTTPS, .env, kcadm)
if [ -n "$PROD_DOMAIN" ]; then
  GRC_INSTALL=1 ./configurar-dominio.sh "$PROD_DOMAIN" "$PROD_AUTH" "$PROD_EMAIL"
fi

$DC ps
if [ -n "$PROD_DOMAIN" ]; then
  echo "Portal:   https://${PROD_DOMAIN}"
  echo "Keycloak: https://${PROD_AUTH}"
else
  echo "Portal:   https://localhost   (http://localhost e :8080 redirecionam pra cá)"
  echo "Login:    https://localhost/auth  (mesma origem — um só certificado)"
  # ── Confiança na CA interna: sem isto o navegador exibe aviso e, com HSTS,
  #    o aviso vira intransponível em Chrome/Safari/Edge. É o passo que torna
  #    o HTTPS local utilizável em QUALQUER navegador, sem o usuário digitar nada.
  echo
  if [ "$(id -u)" -eq 0 ]; then
    ./scripts/confiar-ca.sh || true
  elif command -v sudo >/dev/null 2>&1; then
    echo "Para o HTTPS abrir SEM aviso em todos os navegadores, preciso confiar"
    echo "na CA interna do appliance (pede a sua senha de administrador):"
    sudo ./scripts/confiar-ca.sh || {
      echo "  ! CA não instalada — o navegador vai exibir aviso de certificado."
      echo "    Você pode rodar depois: sudo ./scripts/confiar-ca.sh"; }
  else
    echo "→ Rode depois, para tirar o aviso de certificado: sudo ./scripts/confiar-ca.sh"
  fi
  echo
  echo "  Domínio próprio do cliente (certificado público): área admin →"
  echo "  Domínio & Certificado, ou ./configurar-dominio.sh grc.cliente.com.br"
fi
echo "Usuário: $(grep '^MASTER_EMAIL=' .env|cut -d= -f2-)"
echo "Senha:   $(grep '^MASTER_PASSWORD=' .env|cut -d= -f2-)"
if [ "$IA" = "1" ]; then
  echo "Analista IA: ATIVO (LLM local ${MODEL:-qwen2.5:1.5b})"
else
  echo "Analista IA: motor semântico embarcado ativo. Para o LLM local: rode ./install.sh de novo e responda 's'."
fi
