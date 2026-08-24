#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# Plano de controle do Traçado. Observa /control/request.json (escrito
# SÓ pelo portal, após autenticação de admin) e chama aplicar-dominio.sh.
# O intent é DADO validado, nunca comando: a lógica de aplicação é fixa.
# ════════════════════════════════════════════════════════════════════
set -u
CONTROL=/control
PROJ="${HOST_PROJECT_DIR:?HOST_PROJECT_DIR não definido}"
# uid do processo do portal (container endurecido roda como não-root): ele
# precisa poder GRAVAR o intent no canal de controle. O configurador é root,
# então ajusta o dono do canal para o portal.
PORTAL_UID="${PORTAL_UID:-10001}"
mkdir -p "$CONTROL/upload"
chown -R "$PORTAL_UID:$PORTAL_UID" "$CONTROL" 2>/dev/null || chmod -R 0777 "$CONTROL" 2>/dev/null || true
[ -f "$CONTROL/status.json" ] || \
  printf '{"state":"idle","id":"","applied_id":"","message":"aguardando configuração","ts":0}\n' > "$CONTROL/status.json"

last="$(jq -r '.applied_id // ""' "$CONTROL/status.json" 2>/dev/null)"
echo "[configurator] pronto · projeto=$PROJ · último aplicado='${last}'"

while true; do
  if [ -f "$CONTROL/request.json" ]; then
    id="$(jq -r '.id // empty' "$CONTROL/request.json" 2>/dev/null)"
    if [ -n "$id" ] && [ "$id" != "$last" ]; then
      echo "[configurator] novo pedido id=$id — aplicando"
      if bash "$PROJ/aplicar-dominio.sh" "$CONTROL/request.json" "$CONTROL/status.json"; then
        echo "[configurator] id=$id OK"
      else
        echo "[configurator] id=$id FALHOU (ver status.json)"
      fi
      # marca como processado mesmo em falha, para não repetir em loop;
      # um novo pedido (id novo) tenta de novo.
      last="$id"
    fi
  fi
  sleep 3
done
