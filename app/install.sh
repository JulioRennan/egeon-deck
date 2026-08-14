#!/usr/bin/env bash
# Instala o Egeon Deck estável em /Applications, compilado em release.
#
#   ./install.sh
#
# Depois disto, o app de verdade é o instalado — o `build/` do repositório existe
# para desenvolvimento. Rodar os dois ao mesmo tempo não funciona: mesmo bundle
# id, mesmo `~/.egeon`, mesmo socket e mesma porta de code-server, os dois
# brigando pelos mesmos arquivos.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

DESTINO="/Applications/Egeon Deck.app"
[ -w /Applications ] || DESTINO="$HOME/Applications/Egeon Deck.app"

# Encerrar ANTES de qualquer coisa tocar em bundle.
#
# Isto já custou uma vez: o `make.sh` faz `rm -rf` no `build/EgeonDeck.app`, e
# apagar o executável de um app vivo o mata na validação de assinatura da página
# seguinte — pulando o `applicationWillTerminate`, que é onde o sessions.json é
# gravado e o code-server encerrado. Avisar depois de rodar o make é avisar depois
# do estrago.
#
# Vale para os dois lugares: o de `build/` e o já instalado. Ambos são o flavor
# estável, dividem `~/.egeon`, o socket e a porta 8391.
encerrar() {
  local padrao="$1" nome="$2"
  pgrep -f "$padrao" >/dev/null || return 0
  osascript -e "tell application \"$nome\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do
    pgrep -f "$padrao" >/dev/null || break
    sleep 0.2
  done
  pgrep -f "$padrao" >/dev/null && pkill -f "$padrao" || true
  echo "encerrado: $nome"
}

encerrar "build/EgeonDeck.app/Contents/MacOS/EgeonDeck" "EgeonDeck"
encerrar "$DESTINO/Contents/MacOS/EgeonDeck" "Egeon Deck"

./make.sh release stable

mkdir -p "$(dirname "$DESTINO")"

rm -rf "$DESTINO"
cp -R "build/EgeonDeck.app" "$DESTINO"

echo
echo "instalado: $DESTINO"
echo "abra por Spotlight, pelo Launchpad, ou:"
echo "  open -a \"$DESTINO\""
