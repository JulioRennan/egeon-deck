#!/usr/bin/env bash
# Empacota o app para Linux (decisão 52): compila o core e a UI em release e
# gera, em dist/, o AppImage e o .deb da arquitetura em que roda.
#
#   scripts/linux/run.sh scripts/linux/package.sh x86_64|aarch64
#
# Roda dentro do container (scripts/linux/Dockerfile), que já tem Rust, Zig e
# Flutter. A arquitetura é a da máquina: não há compilação cruzada — o CI usa
# um runner de cada.
set -euo pipefail

ARCH=${1:?uso: package.sh x86_64|aarch64}
[ "$ARCH" = "$(uname -m)" ] || { echo "erro: pedi $ARCH numa máquina $(uname -m)"; exit 1; }
case "$ARCH" in
  x86_64) FLUTTER_ARCH=x64; DEB_ARCH=amd64 ;;
  aarch64) FLUTTER_ARCH=arm64; DEB_ARCH=arm64 ;;
  *) echo "arquitetura desconhecida: $ARCH"; exit 1 ;;
esac

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' rust/Cargo.toml | head -1)
UI_VERSION=$(sed -n 's/^version: \([^+]*\).*/\1/p' ui/pubspec.yaml)
if [ -n "${EGEON_PACKAGE_VERSION:-}" ]; then
  # Ensaio do pacote fora de uma release: a versão do repositório só sobe com
  # o pedido de release, e as duas só batem a partir daí.
  VERSION=$EGEON_PACKAGE_VERSION
else
  [ "$VERSION" = "$UI_VERSION" ] || { echo "erro: core $VERSION e UI $UI_VERSION divergem"; exit 1; }
fi

# appimagetool em versão fixa e conferida.
APPIMAGETOOL_VERSION=1.9.0
case "$ARCH" in
  x86_64) APPIMAGETOOL_SHA256=46fdd785094c7f6e545b61afcfb0f3d98d8eab243f644b4b17698c01d06083d1 ;;
  aarch64) APPIMAGETOOL_SHA256=04f45ea45b5aa07bb2b071aed9dbf7a5185d3953b11b47358c1311f11ea94a96 ;;
esac

DIST="$ROOT/dist"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$DIST"

echo "== core $VERSION ($ARCH)"
cargo build --release --manifest-path rust/Cargo.toml -p egeon-app -p egeon-cli
CORE_DIR="${CARGO_TARGET_DIR:-rust/target}/release"

echo "== UI"
(cd ui && flutter build linux --release)
BUNDLE="ui/build/linux/$FLUTTER_ARCH/release/bundle"
# O executável da UI é o único na raiz do bundle além do core que entra agora.
UI_BIN=$(find "$BUNDLE" -maxdepth 1 -type f -perm -u+x | head -1)
[ -n "$UI_BIN" ] || { echo "erro: sem executável em $BUNDLE"; exit 1; }
UI_NAME=$(basename "$UI_BIN")
# O lançador da UI procura o core ao lado do próprio executável, como no .app.
install -m 755 "$CORE_DIR/egeon-app" "$CORE_DIR/egeon" "$BUNDLE/"

ICON="$ROOT/design/brand/logo/app-icon.png"
# O runner do release se chama assim no X11 (WM_CLASS) e no Wayland (app_id,
# g_set_prgname); a dock só junta a janela ao lançador, com o ícone, se o
# .desktop casar com ele.
APP_ID=dev.duckcoder.egeondeck.next
desktop() {
  cat <<EOF
[Desktop Entry]
Type=Application
Name=Egeon Deck
Comment=Canvas de terminais e agentes de IA
Exec=$1
Icon=egeon-deck
Categories=Development;
Terminal=false
StartupWMClass=$APP_ID
EOF
}

echo "== AppImage"
APPDIR="$WORK/AppDir"
mkdir -p "$APPDIR/usr/lib/egeon-deck"
cp -a "$BUNDLE/." "$APPDIR/usr/lib/egeon-deck/"
cat > "$APPDIR/AppRun" <<EOF
#!/bin/sh
HERE=\$(dirname "\$(readlink -f "\$0")")
exec "\$HERE/usr/lib/egeon-deck/$UI_NAME" "\$@"
EOF
chmod +x "$APPDIR/AppRun"
# O .desktop da raiz é como o core identifica o AppImage baixado: o nome é o
# identificador do app e a X-AppImage-Version, a versão (o Info.plist do macOS).
desktop egeon-deck > "$APPDIR/$APP_ID.desktop"
echo "X-AppImage-Version=$VERSION" >> "$APPDIR/$APP_ID.desktop"
cp "$ICON" "$APPDIR/egeon-deck.png"

TOOL="$WORK/appimagetool"
curl -sSfL -o "$TOOL" \
  "https://github.com/AppImage/appimagetool/releases/download/$APPIMAGETOOL_VERSION/appimagetool-$ARCH.AppImage"
echo "$APPIMAGETOOL_SHA256  $TOOL" | sha256sum -c - >/dev/null \
  || { echo "erro: appimagetool $APPIMAGETOOL_VERSION com sha256 diferente"; exit 1; }
chmod +x "$TOOL"
# Sem FUSE no container, o próprio appimagetool se extrai e roda; ele lê a
# arquitetura do ambiente.
export ARCH
"$TOOL" --appimage-extract-and-run --no-appstream \
  "$APPDIR" "$DIST/EgeonDeck-linux-$ARCH.AppImage"

echo "== .deb"
# O Debian ordena 2.0.0-alpha.1 depois da 2.0.0; com ~ ela vem antes, como no SemVer.
DEB_VERSION=${VERSION/-/\~}
PKG="$WORK/deb"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/egeon-deck" "$PKG/usr/bin" \
  "$PKG/usr/share/applications" "$PKG/usr/share/pixmaps"
cp -a "$BUNDLE/." "$PKG/opt/egeon-deck/"
ln -s "/opt/egeon-deck/$UI_NAME" "$PKG/usr/bin/egeon-deck"
desktop /usr/bin/egeon-deck > "$PKG/usr/share/applications/$APP_ID.desktop"
# O ícone é 1024×1024, fora dos tamanhos do tema hicolor; pixmaps aceita qualquer um.
cp "$ICON" "$PKG/usr/share/pixmaps/egeon-deck.png"
# O Flutter abre a libEGL e a GLES com dlopen ao criar a janela: o ldd não
# as vê, e sem elas a UI morre no Ubuntu mínimo. O zsh é o shell de todo
# terminal do Egeon (/bin/zsh, como no macOS), e o Ubuntu não o traz.
cat > "$PKG/DEBIAN/control" <<EOF
Package: egeon-deck
Version: $DEB_VERSION
Architecture: $DEB_ARCH
Maintainer: Duck Coder Tecnologia
Depends: libgtk-3-0, libegl1, libgles2, zsh
Section: devel
Priority: optional
Homepage: https://github.com/JulioRennan/egeon-deck
Description: Egeon Deck — canvas de terminais e agentes de IA
 Cada nó do canvas é uma ferramenta de trabalho real: terminal, agente de IA,
 navegador. Atualiza pelo apt ou baixando a versão nova; não se troca sozinho.
EOF
dpkg-deb --root-owner-group --build "$PKG" "$DIST/egeon-deck_${VERSION}_${DEB_ARCH}.deb" >/dev/null

ls -la "$DIST"
