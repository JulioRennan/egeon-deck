#!/usr/bin/env bash
# Recompila, encerra e sobe de novo — o flavor DEV por padrão, como o dev.sh do
# Swift.
#
#   ui/scripts/dev.sh [debug|release] [dev|stable]
#
# Dev por padrão de propósito: é ele que se derruba a cada mudança. O estável
# fica de pé com os seus agentes, e é de lá que você pede as mudanças.
set -euo pipefail

UI_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$UI_DIR"

CONFIG="${1:-debug}"
FLAVOR="${2:-dev}"

case "$FLAVOR" in
  stable) APP_NAME="EgeonDeck Next";     HOME_DIR="$HOME/.egeon-next" ;;
  dev)    APP_NAME="EgeonDeck Next Dev"; HOME_DIR="$HOME/.egeon-next-dev" ;;
  *)      echo "flavor desconhecido: $FLAVOR (use dev ou stable)"; exit 1 ;;
esac

APP="$UI_DIR/build/$APP_NAME.app"
# O caminho do bundle distingue os dois processos: o executável tem o mesmo
# nome nos dois.
UI_PATTERN="$APP_NAME.app/Contents/MacOS/EgeonDeck Next"
CORE_PATTERN="$APP_NAME.app/Contents/MacOS/egeon-app"

# Compilar antes de derrubar: build quebrado com o app já morto te deixa sem
# nada.
fvm flutter build macos "--$CONFIG"

if pgrep -f "$UI_PATTERN" >/dev/null; then
  # A UI não guarda estado: quem grava o workbenches.json é o core, que sai
  # sozinho e em ordem quando o cano do stdin fecha com a morte da UI. Por isso
  # SIGTERM basta, sem o `osascript … quit` que o Swift precisava.
  pkill -TERM -f "$UI_PATTERN" || true
  for _ in $(seq 1 50); do
    pgrep -f "$UI_PATTERN" >/dev/null || pgrep -f "$CORE_PATTERN" >/dev/null || break
    sleep 0.2
  done
  if pgrep -f "$CORE_PATTERN" >/dev/null; then
    echo "aviso: o core não saiu em 10 s; mandando SIGTERM a ele"
    pkill -TERM -f "$CORE_PATTERN" || true
    while pgrep -f "$CORE_PATTERN" >/dev/null; do sleep 0.2; done
  fi
  echo "app anterior encerrado ($FLAVOR)"
fi

SKIP_BUILD=1 "$UI_DIR/scripts/make.sh" "$CONFIG" "$FLAVOR"

open -a "$APP"
echo "subiu: $APP"
echo "log:   tail -f $HOME_DIR/egeon.log"
