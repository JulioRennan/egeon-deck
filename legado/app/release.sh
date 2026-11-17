#!/usr/bin/env bash
# Publica a release de uma tag no GitHub: os zips e o texto do CHANGELOG.
#
#   ./release.sh v1.5.0 ["título curto"]
#
# Compila a PARTIR DA TAG, numa worktree temporária, e não do que está aberto
# aqui: release com o código de uma tag e o binário de outro commit é o tipo de
# erro que só aparece na máquina de quem baixou. Serve também para publicar
# tags antigas que ficaram sem release.
#
# Sobe quatro arquivos: os dois com a versão no nome (histórico), o
# `EgeonDeck.zip`, de nome fixo — é o que `releases/latest/download/EgeonDeck.zip`
# entrega, e por onde o botão do site baixa sempre a última — e a assinatura dele,
# sem a qual o atualizador do app recusa a versão (ADR-089). Release que já existe
# tem os arquivos substituídos e o texto atualizado.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

TAG="${1:?uso: ./app/release.sh vX.Y.Z [\"título curto\"]}"
VERSAO="${TAG#v}"
TITULO="${2:-}"

git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "erro: a tag $TAG não existe" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "erro: gh sem login (gh auth login)" >&2; exit 1; }
# Antes do build: descobrir que falta a chave depois de compilar custa minutos.
swift tools/release-key.swift public >/dev/null || { echo "erro: sem a chave de release no Keychain (tools/release-key.swift)" >&2; exit 1; }

# O texto da versão no CHANGELOG da tag: da seção [X.Y.Z] até a próxima.
NOTAS="$(mktemp)"
git show "$TAG:CHANGELOG.md" | awk -v v="$VERSAO" '
  $0 ~ "^## \\[" v "\\]" { dentro = 1; next }
  dentro && /^## \[/ { exit }
  dentro { print }' | sed '/./,$!d' > "$NOTAS"
[ -s "$NOTAS" ] || { echo "erro: o CHANGELOG de $TAG não tem a seção [$VERSAO]" >&2; exit 1; }

OBRA="$(mktemp -d)/egeon-$TAG"
trap 'git worktree remove --force "$OBRA" >/dev/null 2>&1 || true; rm -f "$NOTAS"' EXIT
git worktree add --detach "$OBRA" "$TAG" >/dev/null

( cd "$OBRA/app" && ./dist.sh universal "$TAG" && ./dist.sh arm "$TAG" ) >/dev/null
SAIDA="$OBRA/app/dist"
# Tag antiga não tem o `cp` do nome fixo no dist.sh dela.
cp "$SAIDA/EgeonDeck-$TAG-universal.zip" "$SAIDA/EgeonDeck.zip"
swift tools/release-key.swift sign "$SAIDA/EgeonDeck.zip" >/dev/null
ARQUIVOS=("$SAIDA/EgeonDeck-$TAG-universal.zip" "$SAIDA/EgeonDeck-$TAG-arm.zip" "$SAIDA/EgeonDeck.zip" "$SAIDA/EgeonDeck.zip.sig")

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "${ARQUIVOS[@]}" --clobber
  gh release edit "$TAG" --notes-file "$NOTAS" ${TITULO:+--title "$TAG — $TITULO"}
else
  gh release create "$TAG" "${ARQUIVOS[@]}" --notes-file "$NOTAS" --title "$TAG${TITULO:+ — $TITULO}"
fi

# A release mais nova por data pode não ser a da maior versão (publicar uma tag
# antiga depois): o GitHub decide a "latest" pela data, então ela é marcada à mão.
ULTIMA="$(git tag --list 'v*' --sort=-v:refname | head -1)"
if [ "$TAG" = "$ULTIMA" ]; then gh release edit "$TAG" --latest >/dev/null; fi

echo "publicada: $(gh release view "$TAG" --json url -q .url)"
