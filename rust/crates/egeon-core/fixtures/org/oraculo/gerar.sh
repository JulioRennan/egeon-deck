#!/bin/bash
# Regenera `../esperado/` com o código real do Swift. Só precisa do `swiftc` do
# macOS; não toca em nada fora de uma pasta temporária e de `../esperado/`.
#
#   ./gerar.sh            reescreve ../esperado a partir de ../entrada
#   ./gerar.sh <e> <s>    lê <e> e escreve em <s> (a conferência do que o
#                         Rust gravou: veja conferir.sh)
set -euo pipefail

aqui="$(cd "$(dirname "$0")" && pwd)"
raiz="$(cd "$aqui/../../../../../.." && pwd)"
fontes="$raiz/legado/app/Sources/EgeonDeck/Features"
entrada="${1:-$aqui/../entrada}"
saida="${2:-$aqui/../esperado}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A parte do main.swift que monta a linha de comando e o catálogo do nó, tal
# como está, num enum à parte: no app ela é privada do AppDelegate.
python3 -I - "$raiz/legado/app/Sources/EgeonDeck/main.swift" "$tmp/Launch.swift" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if "/// Como este nó fala com os outros, para o system prompt." in l)
end = next(i for i, l in enumerate(lines) if "/// Garante que um nó de agente tenha id de bancada" in l)
body = "\n".join(lines[start:end]).replace("private static", "static")
open(sys.argv[2], "w", encoding="utf-8").write("import Foundation\n\nenum Launch {\n" + body + "\n}\n")
PY

# O `shellQuote` do Environment.swift, como está: o arquivo inteiro puxa o
# ControlSocket e a CLI, que não fazem parte do que se confere aqui.
python3 -I - "$raiz/legado/app/Sources/EgeonDeck/Core/Models/Environment.swift" "$tmp/AppEnvironment.swift" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if "static func shellQuote" in l)
end = next(i for i in range(start, len(lines)) if lines[i].strip() == "}")
body = "\n".join(lines[start:end + 1])
open(sys.argv[2], "w", encoding="utf-8").write("import Foundation\n\nenum AppEnvironment {\n" + body + "\n}\n")
PY

export ORACULO_HOME="$tmp/home"
mkdir -p "$ORACULO_HOME"

swiftc -O -o "$tmp/oraculo" \
    "$aqui/main.swift" "$aqui/Stubs.swift" "$tmp/Launch.swift" "$tmp/AppEnvironment.swift" \
    "$fontes/Nodes/Features/AgentNode/Models/AgentProfile.swift" \
    "$fontes/Nodes/Features/AgentNode/Models/AgentRules.swift" \
    "$fontes/Nodes/Features/AgentNode/Models/ModelCatalog.swift" \
    "$fontes/Nodes/Features/AgentNode/Models/ModelChoice.swift" \
    "$fontes/Nodes/Features/AgentNode/Features/ClaudeCode/Models/ClaudeProfile.swift" \
    "$fontes/Notifications/Models/HookEvent.swift" \
    "$fontes/Usage/Models/PriceTable.swift" \
    "$fontes/Usage/Models/TokenUsage.swift" \
    "$fontes/Trace/Controllers/ShellHook.swift" \
    "$fontes/Workspace/Models/WorkspaceConfig.swift" \
    "$fontes/Workspace/Models/WorkspaceStore.swift" \
    "$fontes/Workbench/Models/WorkbenchConfig.swift" \
    "$fontes/Workbench/Models/WorkbenchStore.swift" \
    "$fontes/Workbench/Models/WorkbenchColor.swift" \
    "$fontes/Workbench/Models/WorkbenchTemplate.swift" \
    "$fontes/Workbench/Models/ViewMode.swift" \
    "$fontes/Workbench/Models/WorkbenchClock.swift" \
    "$fontes/Nodes/Models/NodeConfig.swift" \
    "$fontes/Nodes/Models/NodeTemplate.swift" \
    "$fontes/Nodes/Models/RetiredNode.swift" \
    "$fontes/Canvas/Models/EdgeConfig.swift"

rm -rf "$saida"
"$tmp/oraculo" "$entrada" "$saida"
echo "esperado gravado em $saida"
