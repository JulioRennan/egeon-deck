# O Linux de desenvolvimento e de CI do Egeon Deck: compila o core (Rust, com o
# libghostty-vt feito com Zig) e a UI (Flutter, runner GTK). A mesma base do
# runner do GitHub (Ubuntu 22.04), para o que passa aqui passar lá.
FROM ubuntu:22.04

ARG FLUTTER_VERSION=3.50.0
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip file build-essential pkg-config \
      clang cmake ninja-build libgtk-3-dev liblzma-dev libstdc++-12-dev \
      libdbus-1-dev libfuse2 zsh dpkg-dev fakeroot desktop-file-utils netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal -c clippy,rustfmt
ENV PATH=/root/.cargo/bin:$PATH

# Pelo git, e não pelo tarball: o tarball oficial é só x86_64, e o runner
# arm64 precisa do mesmo SDK.
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter \
 && /opt/flutter/bin/flutter config --no-analytics --enable-linux-desktop \
 && /opt/flutter/bin/flutter precache --linux
ENV PATH=/opt/flutter/bin:$PATH

# O Zig compila o libghostty-vt (não há binário oficial para Linux); a 1.0.1
# pede Zig 0.17.x. Fica por último para trocar a versão sem baixar o Flutter
# de novo.
ARG ZIG_VERSION=0.17.0
RUN arch=$(uname -m) \
 && case "$arch" in \
      x86_64) sum=1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026 ;; \
      aarch64) sum=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8 ;; \
    esac \
 && curl -sSfL "https://ziglang.org/download/${ZIG_VERSION}/zig-${arch}-linux-${ZIG_VERSION}.tar.xz" -o /tmp/zig.tar.xz \
 && echo "$sum  /tmp/zig.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/zig && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 && rm /tmp/zig.tar.xz
ENV PATH=/opt/zig:$PATH

# O repositório entra montado; o git reclama de dono diferente sem isto.
RUN git config --global --add safe.directory '*'
WORKDIR /src
