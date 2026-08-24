# Plano de controle do Traçado — único componente com acesso ao Docker.
# Mínimo: cliente Docker + compose + jq + python3 para as edições de config.
FROM docker:27-cli
RUN apk add --no-cache bash jq python3 docker-cli-compose
COPY watch.sh /usr/local/bin/watch.sh
RUN chmod +x /usr/local/bin/watch.sh
ENTRYPOINT ["watch.sh"]
