#!/usr/bin/env python3
"""Gera docs/migracao/paridade.md: cada teste de legado/app/Tests e onde foi portado.

Uso (da raiz do repositório):  python3 -I docs/migracao/gerar-paridade.py

Entrada:
  - legado/app/Tests/EgeonDeckTests/*.swift      os testes do Swift (func test…)
  - rust/crates/**/*.rs                          #[test] e #[tokio::test]
  - ui/test/**/*_test.dart                       test(...) e testWidgets(...)
  - docs/migracao/paridade-manual*.json          o que o casamento por nome não alcança

O casamento automático compara o nome do teste do Swift, em snake_case, com o nome
da função de teste em Rust (exato; ou por palavras em comum, marcado como
"provável"). O que não casa vai para o manual: `{"Classe.testNome": {"rust": [...],
"dart": [...], "nao": "motivo", "falta": "o que a ligação não prova"}}`. Quem faltar nos dois aparece como LACUNA.
"""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SWIFT = ROOT / "legado/app/Tests/EgeonDeckTests"
OUT = ROOT / "docs/migracao/paridade.md"


def swift_tests():
    out = []
    for path in sorted(SWIFT.glob("*.swift")):
        cls = None
        for n, line in enumerate(path.read_text(encoding="utf-8").split("\n"), 1):
            m = re.match(r"\s*(?:@MainActor\s+)?(?:final\s+)?class\s+(\w+)\s*:\s*XCTestCase", line)
            if m:
                cls = m.group(1)
                continue
            m = re.match(r"\s*func\s+(test\w*)\s*\(", line)
            if m and cls:
                out.append({"file": path.name, "class": cls, "name": m.group(1), "line": n})
    return out


def rust_tests():
    out = []
    for path in sorted((ROOT / "rust/crates").rglob("*.rs")):
        if "target" in path.parts or ".omc" in path.parts:
            continue
        lines = path.read_text(encoding="utf-8").split("\n")
        for i, line in enumerate(lines):
            if re.match(r"\s*#\[(tokio::)?test", line):
                for j in range(i + 1, min(i + 6, len(lines))):
                    m = re.match(r"\s*(?:pub\s+)?(?:async\s+)?fn\s+(\w+)", lines[j])
                    if m:
                        out.append({"name": m.group(1), "path": str(path.relative_to(ROOT)), "line": j + 1})
                        break
    return out


def dart_tests():
    out = []
    for path in sorted((ROOT / "ui/test").rglob("*_test.dart")):
        text = path.read_text(encoding="utf-8")
        for m in re.finditer(r"\b(?:test|testWidgets)\(\s*(['\"])(.*?)\1", text):
            line = text.count("\n", 0, m.start()) + 1
            out.append({"name": m.group(2), "path": str(path.relative_to(ROOT)), "line": line})
    return out


def cited_classes(path):
    """As classes `XTests` que um arquivo de teste cita — os autores do porte
    escrevem "Porte de XTests" no cabeçalho, e é por aí que se acha o destino de
    um teste cujo nome mudou."""
    text = path.read_text(encoding="utf-8")
    return set(re.findall(r"\b([A-Z]\w*Tests)\b", text))


def exists(ref, known, files):
    path, _, name = ref.partition("::")
    return (path, name) in known if name else path in files


def snake(name):
    name = re.sub(r"^test_?", "", name)
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name)
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", s)
    return s.lower().strip("_")


def words(name):
    return {w for w in snake(name).split("_") if len(w) > 1}


def match(test, by_name, rust, hinted=()):
    key = snake(test["name"])
    if key in by_name:
        return by_name[key], "exato"
    target = words(test["name"])
    # Dentro dos arquivos que citam a classe, basta metade das palavras; fora
    # deles, só quase tudo.
    for pool, floor in ((hinted, 0.5), (rust, 0.8)):
        found = best_of(target, pool, floor)
        if found:
            return [found], "provável"
    return None, ""


def best_of(target, pool, floor):
    if len(target) < 2:
        return None
    best, score = None, 0.0
    for item in pool:
        w = words(item["name"])
        if not w:
            continue
        s = len(target & w) / len(target | w)
        if s > score:
            best, score = item, s
    return best if best and score >= floor else None


def main():
    swift = swift_tests()
    rust = rust_tests()
    dart = dart_tests()
    manual = {}
    owners = {}
    for part in sorted((ROOT / "docs/migracao").glob("paridade-manual*.json")):
        data = json.loads(part.read_text(encoding="utf-8"))
        owners.update(data.pop("_dono", {}))
        manual.update(data)
    by_name = defaultdict(list)
    for item in rust:
        by_name[item["name"]].append(item)
    pool = rust + dart
    # O manual cita testes por `arquivo::nome`: referência a teste que não existe
    # (arquivo que ninguém escreveu) não conta como porte.
    known = {(i["path"], i["name"]) for i in pool}
    files = {i["path"] for i in pool}
    cites = defaultdict(set)
    for item in pool:
        pass
    for path in sorted({i["path"] for i in pool}):
        for cls in cited_classes(ROOT / path):
            cites[cls].add(path)

    rows = []
    for t in swift:
        key = f'{t["class"]}.{t["name"]}'
        entry = manual.get(key)
        where, how = [], ""
        if entry:
            if entry.get("nao"):
                status, where, how = "NÃO PORTA", [], entry["nao"]
            else:
                refs = entry.get("rust", []) + entry.get("dart", [])
                alive = [r for r in refs if exists(r, known, files)]
                missing = [r.split("::")[-1] for r in refs if r not in alive]
                where = [f"`{p}`" for p in alive]
                how = entry.get("nota", "manual")
                if entry.get("falta"):
                    status = "PARCIAL"
                    how = "falta: " + entry["falta"]
                elif not missing:
                    status = "PORTADO"
                else:
                    status = "PARCIAL" if alive else "CONFERIR"
                    how = "falta o teste: " + "; ".join(missing)
        else:
            hinted = [i for i in pool if i["path"] in cites.get(t["class"], ())]
            found, kind = match(t, by_name, pool, hinted)
            if found:
                status = "PORTADO" if kind == "exato" else "PROVÁVEL"
                where = [f'`{f["path"]}::{f["name"]}`' for f in found[:3]]
                how = kind
            elif cites.get(t["class"]):
                status = "CONFERIR"
                where = [f"`{p}`" for p in sorted(cites[t["class"]])]
                how = "o arquivo cita a classe; nenhum teste casa pelo nome"
            else:
                status, how = "LACUNA", ""
        rows.append((t, status, where, how))

    count = defaultdict(int)
    for _, s, _, _ in rows:
        count[s] += 1
    by_file = defaultdict(list)
    for r in rows:
        by_file[r[0]["file"]].append(r)

    md = ["# Paridade de testes — Swift → Rust/Flutter", "",
          "Gerado por `docs/migracao/gerar-paridade.py`; o que o casamento por nome não alcança está em "
          "`docs/migracao/paridade-manual.json`. Regerar ao fim de cada marco.", "",
          f"- Testes do Swift (`legado/app/Tests`): **{len(swift)}**",
          f"- Testes em Rust: {len(rust)} · em Dart: {len(dart)}", "",
          "| Situação | Quantos |", "|---|---:|"]
    for s in ["PORTADO", "PARCIAL", "PROVÁVEL", "CONFERIR", "NÃO PORTA", "LACUNA"]:
        md.append(f"| {s} | {count[s]} |")
    md += ["", "PORTADO = casou por nome ou está no manual; PARCIAL = tem o teste de um lado e falta o do outro (o que falta está na linha); PROVÁVEL = casou por palavras (conferir à mão); "
           "CONFERIR = o arquivo de teste cita a classe do Swift, mas nenhum teste casa pelo nome; "
           "NÃO PORTA = o teste não faz sentido fora do AppKit (motivo na linha); LACUNA = ainda sem teste correspondente.", ""]

    gaps = [r for r in rows if r[1] in ("LACUNA", "CONFERIR", "PARCIAL")]
    md += ["## Lacunas e a conferir", ""]
    if not gaps:
        md += ["Nenhuma.", ""]
    else:
        md += ["| Arquivo | Teste | Situação | De quem é |", "|---|---|---|---|"]
        for t, status, *_ in gaps:
            owner = owners.get(t["class"]) or owners.get(t["file"].replace(".swift", ""), "")
            md.append(f'| {t["file"]} | `{t["name"]}` | {status} | {owner} |')
        md.append("")

    md += ["## Por arquivo", ""]
    for file, items in sorted(by_file.items()):
        done = sum(1 for r in items if r[1] in ("PORTADO", "PROVÁVEL"))
        md += [f"### {file} — {done}/{len(items)}", "",
               "| Teste | Situação | Onde / motivo |", "|---|---|---|"]
        for t, status, where, how in items:
            cell = ", ".join(where) if where else ""
            note = f" ({how})" if how and where else (how if how else "")
            md.append(f'| `{t["class"]}.{t["name"]}` | {status} | {cell}{note} |')
        md.append("")
    OUT.write_text("\n".join(md), encoding="utf-8")
    print(f"{len(swift)} testes Swift; " + ", ".join(f"{k}={v}" for k, v in sorted(count.items())))


if __name__ == "__main__":
    sys.exit(main())
