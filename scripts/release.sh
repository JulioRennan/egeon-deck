#!/usr/bin/env bash
# Release do app novo (decisão 52), em dois tempos:
#
#   scripts/release.sh tag X.Y.Z       confere e empurra a tag vX.Y.Z; o GitHub
#                                      Actions compila e cria o rascunho
#   scripts/release.sh publish X.Y.Z   baixa o rascunho, reassina o app do macOS
#                                      com o certificado local, assina cada
#                                      arquivo que o app instala sozinho e publica
#
# A assinatura acontece aqui, e não no CI, porque a chave das atualizações mora
# só no Keychain desta máquina (scripts/release-key.swift). Cada passo que sai
# da máquina pergunta antes.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

MODE=${1:-}
VERSION=${2:-}
[[ "$MODE" =~ ^(tag|publish)$ && "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "uso: scripts/release.sh tag|publish X.Y.Z"; exit 1; }
TAG="v$VERSION"

# Os arquivos que o app troca sozinho levam .sig; o .deb se atualiza à parte.
SIGNED=(
  EgeonDeck-macos-universal.zip
  EgeonDeck-linux-x86_64.AppImage
  EgeonDeck-linux-aarch64.AppImage
)

ask() {
  read -r -p "$1 [s/N] " answer
  [[ "$answer" =~ ^[sS]$ ]] || { echo "parei."; exit 1; }
}

check_versions() {
  local core ui
  core=$(sed -n 's/^version = "\(.*\)"/\1/p' rust/Cargo.toml | head -1)
  ui=$(sed -n 's/^version: \([^+]*\).*/\1/p' ui/pubspec.yaml)
  [ "$core" = "$VERSION" ] || { echo "erro: rust/Cargo.toml está em $core, não $VERSION"; exit 1; }
  [ "$ui" = "$VERSION" ] || { echo "erro: ui/pubspec.yaml está em $ui, não $VERSION"; exit 1; }
  grep -q "^## \[$VERSION\]" CHANGELOG.md \
    || { echo "erro: o CHANGELOG não tem a seção [$VERSION]"; exit 1; }
}

case "$MODE" in
tag)
  check_versions
  git diff --quiet HEAD || { echo "erro: há mudança não commitada"; exit 1; }
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "erro: a tag $TAG já existe"; exit 1; }
  echo "Commit: $(git log -1 --oneline)"
  ask "Criar e empurrar $TAG? O CI compila e cria o rascunho."
  git tag -a "$TAG" -m "$TAG"
  git push origin "$TAG"
  echo "Acompanhe: gh run watch \$(gh run list -w release -L 1 --json databaseId -q '.[0].databaseId')"
  echo "Depois: scripts/release.sh publish $VERSION"
  ;;

publish)
  [ "$(gh release view "$TAG" --json isDraft -q .isDraft)" = "true" ] \
    || { echo "erro: $TAG não é um rascunho (ainda não existe, ou já foi publicada)"; exit 1; }
  swift scripts/release-key.swift public >/dev/null \
    || { echo "erro: sem a chave das atualizações no Keychain"; exit 1; }

  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  gh release download "$TAG" -D "$WORK" -p '*'
  for f in "${SIGNED[@]}"; do
    [ -f "$WORK/$f" ] || { echo "erro: o rascunho não tem $f"; exit 1; }
  done

  # O CI assina o app ad-hoc; o certificado local `egeon-dev` é o que faz o
  # macOS lembrar as permissões entre versões (o mesmo do make.sh).
  SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
            | awk -F'"' '/"egeon-dev"/ { print $2; exit }')
  if [ -n "$SIGN_ID" ]; then
    MAC="$WORK/mac"
    ditto -x -k "$WORK/EgeonDeck-macos-universal.zip" "$MAC"
    APP=$(find "$MAC" -maxdepth 1 -name '*.app' | head -1)
    codesign --force --sign "$SIGN_ID" --preserve-metadata=entitlements,flags "$APP"
    rm "$WORK/EgeonDeck-macos-universal.zip"
    ditto -c -k --keepParent "$APP" "$WORK/EgeonDeck-macos-universal.zip"
    rm -rf "$MAC"
  else
    echo "aviso: sem o certificado egeon-dev; o app do macOS segue com a assinatura ad-hoc do CI"
  fi

  for f in "${SIGNED[@]}"; do
    swift scripts/release-key.swift sign "$WORK/$f" >/dev/null
  done

  ask "Subir os arquivos assinados e PUBLICAR $TAG?"
  UPLOAD=("$WORK/EgeonDeck-macos-universal.zip")
  for f in "${SIGNED[@]}"; do UPLOAD+=("$WORK/$f.sig"); done
  gh release upload "$TAG" --clobber "${UPLOAD[@]}"
  gh release edit "$TAG" --draft=false --latest
  gh release view "$TAG" --json url -q .url
  ;;
esac
