#!/usr/bin/env bash
# Compila e empacota o Egeon Deck.
#
#   ./make.sh [debug|release] [stable|dev]
#
# Dois flavors, dois apps instalados lado a lado. O estável é o que segura os seus
# agentes; o dev é o que se derruba e reconstrói. Sem essa separação, todo rebuild
# mata a sessão em que você está trabalhando.
#
# Bundle + assinatura (ad-hoc) importam: o TCC do macOS guarda a permissão de
# Acessibilidade por identidade de código. Binário solto perde a permissão a cada
# rebuild.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

CONFIG="${1:-debug}"
FLAVOR="${2:-stable}"

case "$FLAVOR" in
  stable) APP_NAME="EgeonDeck";     DISPLAY="Egeon Deck";       BUNDLE_ID="dev.duckcoder.egeondeck" ;;
  dev)    APP_NAME="EgeonDeck Dev"; DISPLAY="Egeon Deck (dev)"; BUNDLE_ID="dev.duckcoder.egeondeck.dev" ;;
  *)      echo "flavor desconhecido: $FLAVOR (use stable ou dev)"; exit 1 ;;
esac

APP="build/$APP_NAME.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# O executável mantém o mesmo nome nos dois: quem distingue os processos é o
# caminho do bundle, e `pgrep -f` casa nele.
cp ".build/$CONFIG/EgeonDeck" "$APP/Contents/MacOS/EgeonDeck"

# Ícone gerado do PNG a cada build, em vez de um .icns commitado: a fonte de
# verdade é uma imagem só, e trocar o ícone é substituir um arquivo.
if [ -f Resources/icon.png ]; then
  mkdir -p "$APP/Contents/Resources"
  WORK=$(mktemp -d)
  SRC="Resources/icon.png"

  # O dev precisa ser reconhecível de relance no Dock, senão você fala com o app
  # errado. A variante é um arquivo commitado, e não gerada aqui, porque gerar
  # exigiria PIL — que não existe no python do sistema, e build não é lugar para
  # dependência que só está na máquina de quem escreveu.
  [ "$FLAVOR" = "dev" ] && [ -f Resources/icon-dev.png ] && SRC="Resources/icon-dev.png"

  SET="$WORK/AppIcon.iconset"
  mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$SRC" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$WORK"
fi

# A extensão do code-server vai dentro do bundle: ela é parte do produto — sem
# ela o .md abre como texto e o request changes não existe —, e quem recebe o app
# copiado não tem o repositório para rodar o install.sh. Quem cria o link na
# pasta de extensões do flavor é o app, no arranque.
#
# `node_modules` junto (2,7 MB) porque a extensão depende do markdown-it em
# runtime e não há passo de bundling aqui.
if [ -d ../extension ]; then
  if [ -d ../extension/node_modules ]; then
    mkdir -p "$APP/Contents/Resources"
    rm -rf "$APP/Contents/Resources/extension"
    cp -R ../extension "$APP/Contents/Resources/extension"
  else
    echo "aviso: ../extension sem node_modules — a extensão NÃO vai no bundle"
    echo "       rode 'npm install' em extension/ e refaça o build"
  fi
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>     <string>$DISPLAY</string>
  <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key>      <string>EgeonDeck</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>0.2</string>
  <key>LSMinimumSystemVersion</key>  <string>14.0</string>
  <key>NSHighResolutionCapable</key> <true/>
  <key>CFBundleIconFile</key>        <string>AppIcon</string>

  <!-- Texto mostrado no diálogo de permissão do macOS. Sem isso o sistema
       mostra um pedido genérico (ou nega direto, em alguns casos). -->
  <key>NSDocumentsFolderUsageDescription</key>
  <string>O $DISPLAY abre os projetos e terminais das suas sessões.</string>
  <key>NSDesktopFolderUsageDescription</key>
  <string>Acesso a projetos que estejam na Mesa.</string>
  <key>NSDownloadsFolderUsageDescription</key>
  <string>Acesso a projetos que estejam em Transferências.</string>

  <!-- O nó de editor carrega http://127.0.0.1 (code-server local).
       Sem esta exceção o ATS bloqueia HTTP e o WKWebView mostra erro. -->
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key> <true/>
  </dict>
</dict>
</plist>
PLIST

# Assinatura: ad-hoc (`-`) gera uma identidade de código NOVA a cada build, e o
# TCC guarda as permissões (Documentos, Acessibilidade) por identidade — então
# todo rebuild vira um app "novo" e o macOS pede tudo de novo.
# Com um certificado fixo, a permissão é concedida uma vez e sobrevive.
#
#   security find-identity -v -p codesigning     # ver identidades disponíveis
#   export EG_SIGN_ID="egeon-dev"                # nome do certificado
SIGN_ID="${EG_SIGN_ID:--}"

if codesign --force --sign "$SIGN_ID" "$APP" >/dev/null 2>&1; then
  if [ "$SIGN_ID" = "-" ]; then
    echo "aviso: assinado ad-hoc — permissões do macOS serão pedidas de novo a cada build"
    echo "       defina EG_SIGN_ID com um certificado de code signing para parar com isso"
  else
    echo "assinado com: $SIGN_ID"
  fi
else
  echo "erro: codesign falhou com identidade '$SIGN_ID'"
  exit 1
fi

echo "pronto: $APP  ($FLAVOR)"
echo "rode:   open -a \"\$PWD/$APP\""
