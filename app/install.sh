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

# /Applications e ponto. O fallback para ~/Applications parecia gentileza e era
# armadilha: instalado nos dois lugares, a máquina fica com DOIS bundles de mesmo
# id, e abrir "Egeon" pelo Spotlight passa a ser sorteio entre eles. Todo bundle
# cujo id não termina em `.dev` é o flavor estável (Flavor.swift resolve pelo
# sufixo), então o sorteado disputa `~/.egeon`, o socket e a porta 8391 com quem
# já está de pé. E a disputa é silenciosa: o socket é roubado no bind e apagado
# na saída do outro, e o sessions.json é reescrito inteiro pelo snapshot de quem
# gravou por último — aresta e nó do outro somem sem uma linha de log.
DESTINO="/Applications/Egeon Deck.app"
if [ ! -w /Applications ]; then
  echo "erro: /Applications não é gravável por $(whoami) — e não há segundo lugar." >&2
  echo "      instalar em ~/Applications criaria um segundo Egeon de mesmo bundle" >&2
  echo "      id, que é justamente o que derruba o socket e come as arestas." >&2
  echo >&2
  echo "      ./make.sh release stable" >&2
  echo "      sudo rm -rf '$DESTINO' && sudo cp -R build/EgeonDeck.app '$DESTINO'" >&2
  exit 1
fi

# Todo bundle que responde pelo flavor estável e não é o instalado. O Spotlight
# acha o que está indexado; os globs cobrem o que ele costuma ignorar — o
# `build/` do repositório — e o lugar de onde um .zip baixado é aberto.
gemeos() {
  { mdfind "kMDItemCFBundleIdentifier == 'dev.duckcoder.*'" 2>/dev/null
    ls -d "$PWD/build"/*.app "$HOME/Applications"/*.app "$HOME/Downloads"/*.app 2>/dev/null
  } | sort -u | while read -r app; do
    [ "$app" = "$DESTINO" ] && continue
    id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
         "$app/Contents/Info.plist" 2>/dev/null) || continue
    case "$id" in
      *.dev)           continue ;;   # o dev tem ~/.egeon-dev e porta 8392: convive
      dev.duckcoder.*) echo "$app|$id" ;;
    esac
  done
}

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
# `vivo` usa `ps ax | grep`, e não `pgrep -f`.
#
# Isto custou um install que não instalou nada: com o bundle em quarentena o macOS
# roda o app de uma cópia em `AppTranslocation`, e ali o `pgrep -f` NÃO acha o
# processo — o `ps ax` acha. O `pgrep` no topo do `encerrar` devolvia "não tem
# ninguém", o app seguia de pé, o `rm -rf` apagava o bundle debaixo dele e o
# `open -a` do fim subia uma SEGUNDA instância disputando ~/.egeon, o socket e a
# porta 8391.
vivo() { ps ax -o pid=,command= | grep -F "$1" | grep -v grep | awk '{print $1}' | head -1; }

encerrar() {
  local padrao="$1" nome="$2"
  # Pelo BUNDLE ID antes de tudo: é o único jeito que não depende do caminho nem
  # do nome de exibição, e é o que alcança a cópia translocada. Pedir quit dá ao
  # app o `applicationWillTerminate`, onde o sessions.json é gravado e o
  # code-server encerrado.
  osascript -e 'tell application id "dev.duckcoder.egeondeck" to quit' >/dev/null 2>&1 || true
  osascript -e "tell application \"$nome\" to quit" >/dev/null 2>&1 || true
  [ -n "$(vivo "$padrao")" ] || { echo "encerrado: $nome"; return 0; }
  for _ in $(seq 1 50); do
    [ -n "$(vivo "$padrao")" ] || break
    sleep 0.2
  done
  [ -n "$(vivo "$padrao")" ] && pkill -f "$padrao" || true
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

# Tirar a quarentena ANTES de abrir, e não depois.
#
# É ela que faz o macOS rodar o app de uma cópia translocada em vez do bundle de
# /Applications. Com o app translocado, a checagem de pid do fim deste script
# procura um caminho que não existe no processo e conclui "nenhum processo de pé"
# num install que deu certo — e a próxima reinstalação cai no buraco do `pgrep`
# descrito acima.
xattr -dr com.apple.quarantine "$DESTINO" 2>/dev/null || true

# O bundle que o `make.sh` acabou de gerar em `build/` é gêmeo do instalado:
# mesmo id, mesmo `~/.egeon`, mesma porta. Deixá-lo em disco é deixar um segundo
# Egeon estável ao alcance de um duplo clique no Finder. Quem quer depurar o
# estável do repositório roda `./dev.sh debug stable`, que o reconstrói na hora.
rm -rf "build/EgeonDeck.app"

# Cópia solta é a raiz do estrago que motivou esta varredura: um .zip aberto em
# ~/Downloads, ou desempacotado direto em /Applications, vira um Egeon COM
# quarentena — e app com quarentena o macOS roda de uma cópia translocada, que
# nem aparece nos caminhos que este script conhece. Foram duas instâncias
# estáveis vivas ao mesmo tempo, e o socket morreu em silêncio.
gemeados=$(gemeos || true)
if [ -n "$gemeados" ]; then
  echo
  echo "AVISO: outros bundles respondem pelo flavor estável — mesmo ~/.egeon,"
  echo "       mesmo socket, mesma porta 8391:"
  echo "$gemeados" | while IFS='|' read -r app id; do
    marca=""
    xattr "$app" 2>/dev/null | grep -q com.apple.quarantine &&
      marca="   ← em quarentena: roda translocado"
    echo "       $app  ($id)$marca"
  done
  echo
  if [ "${EG_PURGE:-}" = "1" ]; then
    echo "$gemeados" | while IFS='|' read -r app id; do
      rm -rf "$app" && echo "       apagado: $app"
    done
  else
    echo "       apague-os à mão, ou rode com EG_PURGE=1 para o install apagar."
  fi
fi

# Reabrir é parte da instalação, não sugestão de fim: instalado sem trocar o
# processo é o mesmo que não instalado. E encerra de novo antes, porque `open -a`
# com instância viva não abre nada — só traz para frente a que já está lá.
BIN="$DESTINO/Contents/MacOS/EgeonDeck"
instancia() { vivo "$BIN"; }

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
