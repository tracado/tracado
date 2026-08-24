#!/usr/bin/env bash
# Traçado — duplo clique no macOS (o Finder executa .command no Terminal).
cd "$(dirname "$0")"
chmod +x install.sh scripts/*.sh 2>/dev/null
./install.sh "$@"
echo
echo "Pressione ENTER para fechar."
read -r _
