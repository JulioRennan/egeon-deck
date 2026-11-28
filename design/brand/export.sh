#!/usr/bin/env bash
# Leva o ícone mestre de design/brand/logo para todo lugar que o usa.
# O ícone do app dev (app-icon-dev.png) não é exportado: o ui/scripts/make.sh
# o lê daqui a cada montagem.
#
#   design/brand/export.sh            exporta
#   design/brand/export.sh --check    só diz se algum destino está desatualizado
#
set -euo pipefail

BRAND="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$BRAND/../.." && pwd)"
MASTER="$BRAND/logo/app-icon.png"
APPICON="$ROOT/ui/macos/Runner/Assets.xcassets/AppIcon.appiconset"
SITE="$ROOT/site/assets"

[[ -f "$MASTER" ]] || { echo "falta o mestre: $MASTER" >&2; exit 1; }
size=$(sips -g pixelWidth "$MASTER" | awk '/pixelWidth/ {print $2}')
height=$(sips -g pixelHeight "$MASTER" | awk '/pixelHeight/ {print $2}')
[[ "$size" == 1024 && "$height" == 1024 ]] || {
  echo "o mestre tem de ser PNG 1024 × 1024 (está ${size} × ${height})" >&2
  exit 1
}

# destino:tamanho
TARGETS=(
  "$APPICON/app_icon_16.png:16"
  "$APPICON/app_icon_32.png:32"
  "$APPICON/app_icon_64.png:64"
  "$APPICON/app_icon_128.png:128"
  "$APPICON/app_icon_256.png:256"
  "$APPICON/app_icon_512.png:512"
  "$APPICON/app_icon_1024.png:1024"
  "$SITE/icon.png:1024"
  "$SITE/icon-256.png:256"
)

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

stale=0
for t in "${TARGETS[@]}"; do
  out="${t%:*}"
  px="${t##*:}"
  tmp="$WORK/$(basename "$out")-$px.png"
  # Em 1024 o mestre vai como está: redimensionar reencoda e muda os bytes.
  if [[ "$px" == 1024 ]]; then
    cp "$MASTER" "$tmp"
  else
    sips -z "$px" "$px" "$MASTER" --out "$tmp" >/dev/null
  fi
  if [[ "${1:-}" == "--check" ]]; then
    if ! cmp -s "$tmp" "$out"; then
      echo "desatualizado: ${out#"$ROOT"/}"
      stale=1
    fi
  else
    cp "$tmp" "$out"
    echo "ok  ${out#"$ROOT"/} ($px)"
  fi
done

exit "$stale"
