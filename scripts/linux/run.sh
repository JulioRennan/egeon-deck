#!/usr/bin/env bash
# Roda um comando no Linux de desenvolvimento, com o repositório montado em
# /src. Os alvos de compilação ficam em pastas próprias (rust/target/linux)
# e o que a UI gera (ui/build, .dart_tool, o ephemeral) e os caches em volumes,
# para não brigar com os do macOS.
#
#   scripts/linux/run.sh cargo test --workspace
#   scripts/linux/run.sh bash -lc 'cd ui && flutter build linux'
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
IMAGE=egeon-linux-dev
# EGEON_LINUX_PLATFORM=linux/amd64 compila o x86_64 numa máquina arm64
# (emulado, bem mais lento): imagem, volumes e alvo próprios.
PLATFORM=()
if [ -n "${EGEON_LINUX_PLATFORM:-}" ]; then
  PLATFORM=(--platform "$EGEON_LINUX_PLATFORM")
  IMAGE="$IMAGE-${EGEON_LINUX_PLATFORM##*/}"
  EGEON_LINUX_TARGET_SUFFIX="${EGEON_LINUX_TARGET_SUFFIX:-}-${EGEON_LINUX_PLATFORM##*/}"
fi
docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || docker build ${PLATFORM[@]+"${PLATFORM[@]}"} -t "$IMAGE" "$ROOT/scripts/linux"

TTY=()
[ -t 0 ] && TTY=(-it)
SUFFIX="${EGEON_LINUX_TARGET_SUFFIX:-}"
# O que o `pub get` grava tem caminho absoluto do sistema que o rodou: um
# `pub get` no macOS no meio de um build do container quebrava o build com
# links para /Users/…/.pub-cache. Cada lado fica com a sua cópia, e cada
# sufixo com a dele, para dois agentes não compilarem por cima um do outro.
# Quatro jobs: o Zig e o ld em paralelo estouraram os 7,6 GB da VM do Docker.
# --init: sem um PID 1 que recolha órfãos, o shell que morre vira zumbi, e o
# `ps -p` dos testes o vê vivo (exit_with_stdin estourava o tempo no CI).
# O bash 3.2 do macOS, com set -u, trata array vazio como variável indefinida.
exec docker run --rm --init ${TTY[@]+"${TTY[@]}"} ${PLATFORM[@]+"${PLATFORM[@]}"} \
  -v "$ROOT:/src" \
  -v egeon-linux-cargo:/root/.cargo/registry \
  -v egeon-linux-pub:/root/.pub-cache \
  -v "egeon-linux-ui-ephemeral$SUFFIX:/src/ui/linux/flutter/ephemeral" \
  -v "egeon-linux-dart-tool$SUFFIX:/src/ui/.dart_tool" \
  -v "egeon-linux-ui-build$SUFFIX:/src/ui/build" \
  -e CARGO_TARGET_DIR="/src/rust/target/linux$SUFFIX" \
  -e CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-4}" \
  -w /src "$IMAGE" "$@"
