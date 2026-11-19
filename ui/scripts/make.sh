#!/usr/bin/env bash
# Compila e empacota o app novo — o make.sh do Swift adaptado ao Flutter.
#
#   ui/scripts/make.sh [debug|release] [stable|dev]
#
# Dois flavors, dois apps lado a lado. O estável é o que segura os seus
# agentes; o dev é o que se derruba e reconstrói. Sem essa separação, todo
# rebuild mata a sessão em que você está trabalhando.
#
# O Flutter compila um bundle só (`EgeonDeck Next.app`, com o core dentro pela
# fase do rust/scripts/embed_core.sh); daqui sai a cópia de cada flavor, com
# identificador, nome e ícone próprios. Quem diz ao app que ele é o dev é o
# `EGEON_FLAVOR=dev` no `LSEnvironment` do Info.plist: a UI lê a variável e a
# repassa ao core.
#
# SKIP_BUILD=1 só empacota o que já foi compilado (o dev.sh compila antes de
# derrubar o app que está rodando).
set -euo pipefail

UI_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$UI_DIR"

CONFIG="${1:-debug}"
FLAVOR="${2:-stable}"

case "$CONFIG" in
  debug) PRODUCTS=Debug ;;
  release) PRODUCTS=Release ;;
  *) echo "config desconhecida: $CONFIG (use debug ou release)"; exit 1 ;;
esac

case "$FLAVOR" in
  stable) APP_NAME="EgeonDeck Next";     DISPLAY="Egeon Deck Next";       BUNDLE_ID="dev.duckcoder.egeondeck.next" ;;
  dev)    APP_NAME="EgeonDeck Next Dev"; DISPLAY="Egeon Deck Next (dev)"; BUNDLE_ID="dev.duckcoder.egeondeck.next.dev" ;;
  *)      echo "flavor desconhecido: $FLAVOR (use stable ou dev)"; exit 1 ;;
esac

if [ "${SKIP_BUILD:-}" != "1" ]; then
  # shellcheck disable=SC2086 # DART_DEFINES pode trazer vários --dart-define.
  fvm flutter build macos "--$CONFIG" ${DART_DEFINES:-}
fi

SRC="build/macos/Build/Products/$PRODUCTS/EgeonDeck Next.app"
APP="build/$APP_NAME.app"
[ -d "$SRC" ] || { echo "erro: $SRC não existe (compile sem SKIP_BUILD)"; exit 1; }

rm -rf "$APP"
ditto "$SRC" "$APP"

PLIST="$APP/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }
pb "Set :CFBundleIdentifier $BUNDLE_ID"
pb "Set :CFBundleName $APP_NAME"
pb "Delete :CFBundleDisplayName" 2>/dev/null || true
pb "Add :CFBundleDisplayName string $DISPLAY"
pb "Delete :LSEnvironment" 2>/dev/null || true
if [ "$FLAVOR" = "dev" ]; then
  pb "Add :LSEnvironment dict"
  pb "Add :LSEnvironment:EGEON_FLAVOR string dev"
fi

# O build é o commit, como no Swift: "+" marca build com mudança não commitada.
BUILD="$(git rev-parse --short HEAD 2>/dev/null || echo sem-git)"
git diff --quiet HEAD 2>/dev/null || BUILD="$BUILD+"
pb "Set :CFBundleVersion $BUILD"

# O dev precisa ser reconhecível de relance no Dock, senão você fala com o app
# errado. O ícone vem do do Swift; o .icns sobrepõe o do catálogo de assets.
ICON_SRC="$UI_DIR/../legado/app/Resources/icon-dev.png"
if [ "$FLAVOR" = "dev" ] && [ -f "$ICON_SRC" ]; then
  WORK=$(mktemp -d)
  SET="$WORK/AppIcon.iconset"
  mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ICON_SRC" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIconDev.icns"
  rm -rf "$WORK"
  pb "Delete :CFBundleIconName" 2>/dev/null || true
  pb "Delete :CFBundleIconFile" 2>/dev/null || true
  pb "Add :CFBundleIconFile string AppIconDev"
fi

# Assinatura, como no Swift: o TCC guarda as permissões (Documentos,
# Acessibilidade, microfone) pela identidade de código, e ad-hoc gera uma nova
# a cada build. Com o certificado local `egeon-dev` a permissão sobrevive.
# Só o bundle de fora é reassinado: os frameworks e o core dentro não mudaram,
# e as entitlements do Runner vão junto.
SIGN_ID="${EG_SIGN_ID:-}"
if [ -z "$SIGN_ID" ]; then
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'"' '/"egeon-dev"/ { print $2; exit }')
fi
SIGN_ID="${SIGN_ID:--}"
if ! codesign --force --sign "$SIGN_ID" --preserve-metadata=entitlements,flags "$APP" >/dev/null 2>&1; then
  echo "erro: codesign falhou com identidade '$SIGN_ID'"
  exit 1
fi
[ "$SIGN_ID" = "-" ] && echo "aviso: assinado ad-hoc — o macOS pedirá as permissões de novo a cada build (crie o certificado 'egeon-dev')"

# O LaunchServices guarda o Info.plist de quem já viu: sem registrar de novo, o
# `open` pode subir o dev sem o LSEnvironment novo.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

echo "pronto: ui/$APP  ($FLAVOR, $CONFIG)"
