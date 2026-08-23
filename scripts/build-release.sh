#!/usr/bin/env bash
# Build e assinatura da imagem do Lastro.
#
# Roda na infraestrutura do FORNECEDOR. Produz uma imagem com procedência
# gravada (versão, commit, data, id de build) e, se o cosign estiver
# disponível, a assinatura que permite ao cliente verificar que a imagem veio
# de você e não foi adulterada no caminho.
set -euo pipefail
cd "$(dirname "$0")/.."

PORTAL_SRC="${PORTAL_SRC:-../lastro-portal}"
if [ ! -f "${PORTAL_SRC}/Dockerfile" ]; then
  echo "✗ Código do portal não encontrado em ${PORTAL_SRC}."
  echo "  Clone o repositório privado ao lado deste, ou defina PORTAL_SRC."
  exit 1
fi
# a versão e o commit descrevem o PORTAL, não o appliance — é o portal que vira imagem
VERSION="${VERSION:-$(git -C "${PORTAL_SRC}" describe --tags --always 2>/dev/null || echo 2.1.0)}"
GIT_SHA="$(git -C "${PORTAL_SRC}" rev-parse HEAD 2>/dev/null || echo desconhecido)"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
BUILD_ID="$(date -u +%Y%m%d%H%M%S)-${GIT_SHA:0:7}"
REGISTRY="${REGISTRY:-ghcr.io/lastrogrc}"
IMAGEM="${REGISTRY}/lastro-portal"

sujo=""
if git -C "${PORTAL_SRC}" status --porcelain 2>/dev/null | grep -q .; then
  sujo=" (árvore de trabalho SUJA)"
  echo "⚠  Há alterações não commitadas. Uma imagem gerada de árvore suja não"
  echo "   tem procedência verificável — o commit gravado não descreve o que foi."
  read -rp "   Continuar mesmo assim? [s/N] " r; [ "$r" = "s" ] || exit 1
fi

echo "▸ Versão   : ${VERSION}${sujo}"
echo "▸ Commit   : ${GIT_SHA}"
echo "▸ Build id : ${BUILD_ID}"

docker build \
  --build-arg "VERSION=${VERSION}" \
  --build-arg "GIT_SHA=${GIT_SHA}" \
  --build-arg "BUILD_DATE=${BUILD_DATE}" \
  --build-arg "BUILD_ID=${BUILD_ID}" \
  -t "${IMAGEM}:${VERSION}" -t "${IMAGEM}:latest" \
  "${PORTAL_SRC:-../lastro-portal}"

echo "▸ Imagem construída:"
docker image inspect "${IMAGEM}:${VERSION}" \
  --format '   {{index .Config.Labels "org.opencontainers.image.version"}} · commit {{index .Config.Labels "org.opencontainers.image.revision"}} · build {{index .Config.Labels "br.com.lastro.build_id"}}'

if [ "${PUBLICAR:-nao}" = "sim" ]; then
  docker push "${IMAGEM}:${VERSION}"
  docker push "${IMAGEM}:latest"
  DIGEST="$(docker image inspect "${IMAGEM}:${VERSION}" --format '{{index .RepoDigests 0}}')"
  echo "▸ Publicada: ${DIGEST}"

  if command -v cosign >/dev/null 2>&1; then
    cosign sign --yes "${DIGEST}"
    echo "▸ Assinada com cosign."
    echo "  O cliente verifica com:"
    echo "    cosign verify ${DIGEST} \\"
    echo "      --certificate-identity-regexp '.*' --certificate-oidc-issuer-regexp '.*'"
  else
    echo "⚠  cosign não encontrado — imagem publicada SEM assinatura."
    echo "   Instale com:  brew install cosign   (ou https://docs.sigstore.dev)"
    echo "   Sem assinatura, o cliente não tem como provar que a imagem é sua."
  fi
else
  echo "▸ Não publicada (defina PUBLICAR=sim para enviar ao registro e assinar)."
fi
