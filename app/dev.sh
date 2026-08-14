#!/usr/bin/env bash
# Recompila, encerra e sobe de novo — o flavor DEV por padrão.
#
#   ./dev.sh [debug|release] [dev|stable]
#
# Dev por padrão de propósito: é ele que se derruba a cada mudança. O estável fica
# de pé com os seus agentes, e é de lá que você pede as mudanças. Mexer no estável
# é escolha explícita, porque isso mata a sessão em que você está trabalhando
# (ADR-010: o app segura os pty direto, sem tmux).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

CONFIG="${1:-debug}"
FLAVOR="${2:-dev}"

case "$FLAVOR" in
  stable) APP_NAME="EgeonDeck";     QUIT_NAME="EgeonDeck" ;;
  dev)    APP_NAME="EgeonDeck Dev"; QUIT_NAME="EgeonDeck Dev" ;;
  *)      echo "flavor desconhecido: $FLAVOR (use dev ou stable)"; exit 1 ;;
esac

APP="$PWD/build/$APP_NAME.app"
# O caminho do bundle é o que distingue os dois processos: o executável dentro
# tem o mesmo nome nos dois.
PATTERN="$APP_NAME.app/Contents/MacOS/EgeonDeck"

# Compilar antes de derrubar o app: build quebrado com o app já morto te deixa
# sem nada. E encerrar antes do `make.sh`, que faz `rm -rf` no bundle — apagar o
# executável de um app rodando o mata na validação de assinatura, pulando o
# `applicationWillTerminate` que grava o sessions.json e encerra o code-server.
swift build -c "$CONFIG"

if pgrep -f "$PATTERN" >/dev/null; then
  # `quit` em vez de `pkill`: SIGTERM não passa pelo `applicationWillTerminate`
  # de um app Cocoa, e é lá que o sessions.json é gravado, o code-server é
  # encerrado e as janelas estacionadas são resgatadas.
  osascript -e "tell application \"$QUIT_NAME\" to quit" >/dev/null 2>&1 || true

  # Reabrir antes de o processo sair de fato faz o LaunchServices trazer a
  # instância moribunda para frente em vez de abrir a nova.
  for _ in $(seq 1 50); do
    pgrep -f "$PATTERN" >/dev/null || break
    sleep 0.2
  done

  if pgrep -f "$PATTERN" >/dev/null; then
    echo "aviso: não saiu no pedido educado, matando — o sessions.json pode"
    echo "       perder a última posição de nó arrastada"
    pkill -f "$PATTERN" || true
    while pgrep -f "$PATTERN" >/dev/null; do sleep 0.2; done
  fi
  echo "app anterior encerrado ($FLAVOR)"
fi

./make.sh "$CONFIG" "$FLAVOR"

open -a "$APP"
echo "subiu: $APP"
echo "log:   tail -f ~/egeon$([ "$FLAVOR" = dev ] && echo -dev).log"
