#!/usr/bin/env bash
# Empacota o Egeon Deck para entregar a outra pessoa: um .app num zip.
#
#   ./dist.sh                    universal — roda em Intel e em Apple Silicon
#   ./dist.sh arm                só Apple Silicon, 4 MB menor
#   ./dist.sh universal v0       a versão só nomeia o arquivo
#
# Universal NÃO é mais lento. O binário carrega as duas fatias e o macOS carrega
# só a nativa: num M-series roda o mesmo código do build só-arm, na mesma
# velocidade. O que dobra é o executável (3,9 MB → 8,1 MB) e o tempo de
# compilação. Por isso o padrão é universal, e `arm` existe para quando o
# tamanho importa mais do que alcançar as duas máquinas.
#
# NÃO instala nem abre nada: `install.sh` é para esta máquina, este é para as
# outras.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

MODO="${1:-universal}"
case "$MODO" in
  universal|arm) ;;
  *) echo "modo desconhecido: $MODO (use universal ou arm)"; exit 1 ;;
esac

VERSAO="${2:-$(git describe --tags --always 2>/dev/null || echo dev)}"
SAIDA="dist"
ZIP="$SAIDA/EgeonDeck-$VERSAO-$MODO.zip"

# O app empacotado é o ESTÁVEL: é ele que instala em /Applications e usa
# ~/.egeon. Entregar o flavor dev daria a quem recebe um app que se anuncia como
# "(dev)" e grava noutro lugar.
if [ "$MODO" = universal ]; then
  EG_UNIVERSAL=1 ./make.sh release stable
else
  ./make.sh release stable
fi

APP="build/EgeonDeck.app"
BIN="$APP/Contents/MacOS/EgeonDeck"

# Conferir em vez de confiar: bundle montado a partir de um build antigo passa
# despercebido, e o defeito só aparece na máquina do outro — que é o pior lugar
# para descobrir que faltou uma arquitetura.
arcos=$(lipo -archs "$BIN")
echo
echo "arquiteturas no binário: $arcos"
esperadas="arm64"
[ "$MODO" = universal ] && esperadas="arm64 x86_64"
for esperado in $esperadas; do
  case " $arcos " in
    *" $esperado "*) ;;
    *) echo "erro: faltou $esperado no binário empacotado"; exit 1 ;;
  esac
done

mkdir -p "$SAIDA"
rm -f "$ZIP"
# `ditto` e não `zip`: preserva os metadados do bundle e a assinatura de código,
# que o zip comum embaralha — e assinatura embaralhada é app que não abre.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo
echo "pronto: $ZIP  ($(du -h "$ZIP" | cut -f1))"

cat <<'FIM'

Antes de mandar, leia isto:

O bundle vai assinado ad-hoc e sem notarização. Baixado pela internet, o macOS
põe quarentena e recusa abrir — a mensagem fala em app "danificado", que é
enganosa. Quem receber precisa rodar uma vez:

  xattr -dr com.apple.quarantine "/Applications/Egeon Deck.app"

Para não pedir isso a ninguém, é preciso assinar com um certificado Developer ID
e notarizar na Apple (conta paga):

  EG_SIGN_ID="Developer ID Application: <nome> (<team>)" ./dist.sh
  xcrun notarytool submit <zip> --keychain-profile <perfil> --wait
  xcrun stapler staple "build/EgeonDeck.app"

E o app não é auto-contido: o nó de editor precisa de `code-server` na máquina de
quem recebe, e o nó de agente precisa do CLI que ele já usa. Está no README.
FIM
