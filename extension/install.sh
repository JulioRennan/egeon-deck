#!/usr/bin/env bash
# Instala a extensão no code-server do egeon, apontando para ESTE diretório.
#
#   ./install.sh [stable|dev]
#
# Só é preciso para desenvolver a extensão: quem usa o app instalado já a recebe,
# porque o `make.sh` a copia para dentro do bundle e o app cria o link no
# arranque. O link daqui aponta para o repositório, então editar o código e
# recarregar a janela basta.
#
# Sem vsce e sem marketplace: o code-server varre a pasta de extensões, então
# basta um symlink. A restrição do OpenVSX vale para extensões de terceiros —
# código nosso a gente instala como quiser (ADR-004).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FLAVOR="${1:-stable}"
case "$FLAVOR" in
  stable) CONFIG_DIR="$HOME/.egeon" ;;
  dev)    CONFIG_DIR="$HOME/.egeon-dev" ;;
  *)      echo "flavor desconhecido: $FLAVOR (use stable ou dev)"; exit 1 ;;
esac

DEST_DIR="$CONFIG_DIR/code-server/extensions"
DEST="$DEST_DIR/egeon.spec-0.1.0"

[ -d "$SRC/node_modules/markdown-it" ] || { echo "erro: rode 'npm install' em $SRC"; exit 1; }

mkdir -p "$DEST_DIR"
rm -rf "$DEST"
ln -s "$SRC" "$DEST"

echo "instalado ($FLAVOR): $DEST -> $SRC"
echo "reinicie o code-server (ou o app) para carregar."
