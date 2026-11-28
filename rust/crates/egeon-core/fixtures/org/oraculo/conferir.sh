#!/bin/bash
# O que o Rust grava, o Swift relê sem perda: o teste das fixtures deixa em
# $EGEON_ORG_DUMP os arquivos que gravou, o oráculo os lê e grava de novo com o
# código real do Swift, e os dois têm de ser o mesmo JSON.
#
# Roda a partir de rust/. O alvo do cargo vem de CARGO_TARGET_DIR, se definido.
set -euo pipefail

aqui="$(cd "$(dirname "$0")" && pwd)"
dump="$(mktemp -d)"
reler="$(mktemp -d)"
trap 'rm -rf "$dump" "$reler"' EXIT

EGEON_ORG_DUMP="$dump" cargo test -p egeon-core --lib json_file::fixtures
"$aqui/gerar.sh" "$dump" "$reler" >/dev/null

python3 -I - "$dump" "$reler" <<'PY'
import json, pathlib, sys
rust, swift = map(pathlib.Path, sys.argv[1:])
files = sorted(p.relative_to(rust) for p in rust.rglob("*.json"))
bad = 0

def reading(value):
    # Defeito conhecido do Swift, que o Rust porta: `maxSends: null` não volta
    # ao disco (nem no Swift), e ao reler a chave ausente vira 2. Os dois lados
    # são comparados como a LEITURA os vê.
    if isinstance(value, list):
        for item in value:
            for edge in (item.get("edges") or []) if isinstance(item, dict) else []:
                edge.setdefault("maxSends", 2)
    return value

for f in files:
    # `sessions-*` foi gravado pelo Rust como workbenches.json: o Swift o relê
    # na mesma pasta.
    a = reading(json.loads((rust / f).read_text()))
    b = reading(json.loads((swift / f).read_text()))
    if a != b:
        bad += 1
        print(f"DIFERE: {f}")
print(f"{len(files)} arquivos conferidos, {bad} diferentes")
sys.exit(1 if bad else 0)
PY
