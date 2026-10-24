#!/usr/bin/env bash
# Quadros da janela do Egeon Dev, mesmo coberta por outras: frames.sh <pasta> <segundos> [intervalo]
set -euo pipefail
out="$1"; dur="$2"; step="${3:-0.5}"
mkdir -p "$out"
here="$(cd "$(dirname "$0")" && pwd)"
end=$(( $(date +%s) + dur )); i=0
while [ "$(date +%s)" -lt "$end" ]; do
  read id _ < <("$here/window")
  screencapture -x -o -l "$id" "$(printf '%s/f%05d.png' "$out" "$i")"
  i=$((i+1)); sleep "$step"
done
echo "$i quadros"
