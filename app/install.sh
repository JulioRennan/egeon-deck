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

# O de `build/` cai antes do make: é ele que o `make.sh` apaga.
encerrar "build/EgeonDeck.app/Contents/MacOS/EgeonDeck" "EgeonDeck"

# Compila ANTES de encerrar o instalado. O build não toca no bundle de
# /Applications, então o app — e os agentes dentro dele — continuam de pé pelos
# ~15s de compilação. Encerrar primeiro deixava a janela sem app aberta esse
# tempo todo, e foi assim que um install se perdeu: o app foi reaberto no meio da
# compilação, do bundle antigo, e o `open -a` do fim virou no-op porque já havia
# instância viva. Resultado: bundle novo em disco, processo velho na tela.
./make.sh release stable

mkdir -p "$(dirname "$DESTINO")"

encerrar "$DESTINO/Contents/MacOS/EgeonDeck" "Egeon Deck"

rm -rf "$DESTINO"
cp -R "build/EgeonDeck.app" "$DESTINO"

# Reabrir é parte da instalação, não sugestão de fim: instalado sem trocar o
# processo é o mesmo que não instalado. E encerra de novo antes, porque `open -a`
# com instância viva não abre nada — só traz para frente a que já está lá.
BIN="$DESTINO/Contents/MacOS/EgeonDeck"
instancia() { ps ax -o pid=,command= | grep -F "$BIN" | grep -v grep | awk '{print $1}' | head -1; }

antes=$(instancia)
encerrar "$BIN" "Egeon Deck"
open -a "$DESTINO"

# O processo tem de ser OUTRO: mesmo pid depois do quit significa que ele não
# morreu, e aí o que está na tela continua sendo o executável anterior — que este
# script acabou de apagar debaixo dele. Comparar pid é o bastante porque o
# `encerrar` acima derruba qualquer instância um instante antes do `open`.
sleep 2
agora=$(instancia)

echo
if [ -z "$agora" ]; then
  echo "instalado: $DESTINO"
  echo "AVISO: nenhum processo de pé — abra por Spotlight e confira ~/egeon.log"
elif [ -n "$antes" ] && [ "$agora" = "$antes" ]; then
  echo "AVISO: o app de pé (pid $agora) é o mesmo de antes da instalação — ele não"
  echo "       reiniciou, então segue executando o build anterior. ⌘Q e reabra."
else
  echo "instalado e rodando: $DESTINO (pid $agora)"
fi
