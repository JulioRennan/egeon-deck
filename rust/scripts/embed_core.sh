#!/bin/sh
# Fase de build do Runner (ui/macos): compila o `egeon-app` (o core) e o
# `egeon` (a CLI dos agentes) e os põe dentro do .app, ao lado do executável da
# UI — é onde o lançador da UI procura o core quando EGEON_APP_BIN não está
# posto, e onde o `egeon-app` procura o `egeon` que instala em EGEON_HOME/bin.
#
#   Runner.app/Contents/MacOS/{Runner, egeon-app, egeon}
#
# Chamado pelo Xcode (variáveis CONFIGURATION, TARGET_BUILD_DIR,
# EXECUTABLE_FOLDER_PATH, ARCHS); também roda à mão:
#
#   TARGET_BUILD_DIR=/tmp/x EXECUTABLE_FOLDER_PATH=App.app/Contents/MacOS \
#       CONFIGURATION=Release rust/scripts/embed_core.sh
#
# Debug compila em debug (rápido); Release e Profile, em release. A pasta de
# build do cargo é rust/target/app, para não disputar o lock com quem trabalha
# em rust/ (EGEON_CORE_TARGET_DIR troca).
#
# Assinatura: aqui os binários ficam só com a assinatura avulsa do linker (a do
# `lipo`, refeita por esta fase), que o arm64 exige para executar. Para
# distribuir (Developer ID e notarização) falta assinar os dois com a
# identidade e `--options runtime --timestamp` nesta fase: o Xcode só reassina
# o executável principal e sela o pacote.

set -eu

RUST_DIR=$(cd "$(dirname "$0")/.." && pwd)
DEST=${TARGET_BUILD_DIR:?falta TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH:?falta EXECUTABLE_FOLDER_PATH}

case "${CONFIGURATION:-Release}" in
    Debug*) PROFILE=debug; PROFILE_FLAG="" ;;
    *) PROFILE=release; PROFILE_FLAG="--release" ;;
esac

# O Xcode roda a fase com um PATH curto: o cargo mora em ~/.cargo/bin.
PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH
command -v cargo >/dev/null 2>&1 || { echo "error: cargo não encontrado (instale o Rust: rustup.rs)" >&2; exit 1; }

export CARGO_TARGET_DIR=${EGEON_CORE_TARGET_DIR:-$RUST_DIR/target/app}
# Do ambiente do Xcode, só o que ajuda: CC, LD e afins são do build do Runner,
# e o cargo acha as ferramentas sozinho. O SDKROOT fica: sem ele o `cc` do
# Xcode não acha os cabeçalhos do sistema (o `ring` não compila).
unset CC CXX LD LDPLUSPLUS CPP RUSTFLAGS CARGO_BUILD_TARGET
MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-14.0}
export MACOSX_DEPLOYMENT_TARGET

HOST_ARCH=$(uname -m)
ARCH_LIST=${ARCHS:-$HOST_ARCH}

target_of() {
    case "$1" in
        arm64) echo aarch64-apple-darwin ;;
        x86_64) echo x86_64-apple-darwin ;;
        *) echo "" ;;
    esac
}

INSTALLED=$(rustup target list --installed 2>/dev/null || true)
BUILT_ARCHS=""
for arch in $ARCH_LIST; do
    target=$(target_of "$arch")
    [ -n "$target" ] || continue
    # Alvo que o rustup não tem: o app sobe, mas o core só roda nas outras
    # arquiteturas. Aviso, e não falha, para o build do Flutter nesta máquina.
    if [ -n "$INSTALLED" ] && ! printf '%s\n' "$INSTALLED" | grep -qx "$target"; then
        # EGEON_CORE_TODAS_AS_ARQUITETURAS=1 (processo de release) exige todas:
        # um .app universal com o core só em arm64 abriria sem core num Intel.
        if [ "${EGEON_CORE_TODAS_AS_ARQUITETURAS:-0}" = 1 ]; then
            echo "error: alvo $target não instalado (rustup target add $target)" >&2
            exit 1
        fi
        echo "warning: alvo $target não instalado (rustup target add $target): o core fica de fora para $arch" >&2
        continue
    fi
    # shellcheck disable=SC2086
    (cd "$RUST_DIR" && cargo build $PROFILE_FLAG --target "$target" -p egeon-app -p egeon-cli) || {
        echo "error: cargo build falhou para $target" >&2
        exit 1
    }
    BUILT_ARCHS="$BUILT_ARCHS $arch"
done

[ -n "$BUILT_ARCHS" ] || { echo "error: nenhuma arquitetura do core compilou (ARCHS=$ARCH_LIST)" >&2; exit 1; }

mkdir -p "$DEST"
for binary in egeon-app egeon; do
    set --
    for arch in $BUILT_ARCHS; do
        set -- "$@" "$CARGO_TARGET_DIR/$(target_of "$arch")/$PROFILE/$binary"
    done
    if [ "$#" -eq 1 ]; then
        cp -f "$1" "$DEST/$binary"
    else
        lipo -create "$@" -output "$DEST/$binary"
        # Sem a assinatura avulsa o arm64 não executa: se falhar, o `set -e` derruba.
        codesign --force --sign - "$DEST/$binary" >/dev/null
    fi
    chmod 755 "$DEST/$binary"
done

echo "core embutido em $DEST ($PROFILE,$BUILT_ARCHS)"
