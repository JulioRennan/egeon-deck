#!/usr/bin/env bash
# Sobe o Egeon DEV com bancadas de demonstração, para as fotos do site, sem
# misturar com as suas: a ~/.egeon-dev de verdade fica de lado e volta no `down`.
#
#   site/tools/demo.sh up     guarda a config real e sobe a demonstração
#   site/tools/demo.sh down   encerra e devolve a config real
set -euo pipefail

REAL="$HOME/.egeon-dev"
KEEP="$HOME/.egeon-dev.real"
DEMO="$HOME/egeon-demo"
APP="$(cd "$(dirname "$0")/../../app" && pwd)/build/EgeonDeck Dev.app"
PATTERN="EgeonDeck Dev.app/Contents/MacOS/EgeonDeck"

quit_app() {
  if pgrep -f "$PATTERN" >/dev/null; then
    osascript -e 'tell application "EgeonDeck Dev" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do pgrep -f "$PATTERN" >/dev/null || break; sleep 0.25; done
  fi
  if pgrep -f "$PATTERN" >/dev/null; then echo "o dev não fechou; feche à mão" >&2; exit 1; fi
}

repo() {
  local dir="$DEMO/$1"; shift
  [ -d "$dir/.git" ] && return
  mkdir -p "$dir"
  ( cd "$dir"; "$@"; git init -q; git add -A; git -c user.name=demo -c user.email=demo@egeon commit -qm "início" )
}

case "${1:-}" in
up)
  [ -e "$KEEP" ] && { echo "já existe $KEEP — rode 'down' antes" >&2; exit 1; }
  quit_app
  mv "$REAL" "$KEEP"
  mkdir -p "$REAL"
  for f in agents.json claude-models.json pricing.json; do
    [ -f "$KEEP/$f" ] && cp "$KEEP/$f" "$REAL/"
  done

  repo loja bash -c '
    mkdir -p web/src api/src
    printf "{\n  \"name\": \"loja\",\n  \"private\": true\n}\n" > package.json
    printf "# Loja\n\nVitrine (web/) e API de pedidos (api/).\n" > README.md
    printf "export function Vitrine() {\n  return <main>Produtos</main>\n}\n" > web/src/Vitrine.tsx
    printf "export const rotas = {\n  pedidos: \"/pedidos\",\n}\n" > api/src/rotas.ts'
  repo landing bash -c 'printf "<h1>Landing</h1>\n" > index.html'
  repo app-mobile bash -c 'printf "# App\n" > README.md'

  python3 - "$REAL" "$DEMO" <<'PY'
import json, sys
real, demo = sys.argv[1], sys.argv[2]
ws = [{"id": "d0c0de01", "name": "Duck Coder", "projects": [
    {"id": "p0000001", "name": "loja", "path": f"{demo}/loja"},
    {"id": "p0000002", "name": "landing", "path": f"{demo}/landing"},
    {"id": "p0000003", "name": "app-mobile", "path": f"{demo}/app-mobile"}]}]
def agent(id, x, y, w=620, h=420, **kw):
    return {"type": "agent", "id": id, "agent": "claude", "x": x, "y": y, "w": w, "h": h, **kw}
loja = {"id": "a1000001", "name": "loja", "path": f"{demo}/loja", "project": "p0000001",
        "color": "violet", "tabOrder": 0, "tabActive": True,
        "rules": "Responda em português. Não faça commit sem pedir.",
        "nodes": [
            agent("maestro", 80, 60, 560, 380, maestro=True, model="opus", effort="medium",
                  prompt="Você é o maestro: divide o trabalho da loja entre front, back e revisor."),
            agent("front", 700, 60, model="sonnet", effort="low", cwd="web",
                  prompt="Você cuida da vitrine em React (pasta web/)."),
            agent("back", 700, 520, model="sonnet", effort="low", cwd="api",
                  prompt="Você cuida da API de pedidos (pasta api/)."),
            agent("revisor", 80, 500, 560, 440, model="sonnet", effort="medium",
                  prompt="Você revisa o que front e back entregam, antes do commit."),
            {"type": "web", "id": "preview", "url": "http://127.0.0.1:4173/", "x": 1380, "y": 60, "w": 760, "h": 880},
        ],
        "edges": [{"from": "front", "to": "revisor"}, {"from": "revisor", "to": "front"},
                  {"from": "back", "to": "revisor"}, {"from": "revisor", "to": "back"},
                  {"from": "front", "to": "back"}, {"from": "back", "to": "front"}]}
landing = {"id": "a2000002", "name": "landing", "path": f"{demo}/landing", "project": "p0000002",
           "color": "cyan", "tabOrder": 1,
           "nodes": [agent("copy", 120, 80, model="sonnet", effort="low")]}
mobile = {"id": "a3000003", "name": "app-mobile", "path": f"{demo}/app-mobile", "project": "p0000003",
          "color": "pink", "tabOrder": 2,
          "nodes": [agent("ios", 120, 80, model="sonnet", effort="low")]}
json.dump(ws, open(f"{real}/workspaces.json", "w"), indent=2)
json.dump([loja, landing, mobile], open(f"{real}/workbenches.json", "w"), indent=2)
PY
  open -a "$APP"
  echo "demonstração de pé — a sua config está em $KEEP"
  ;;
down)
  [ -e "$KEEP" ] || { echo "nada a devolver ($KEEP não existe)" >&2; exit 1; }
  quit_app
  rm -rf "$REAL.demo"
  mv "$REAL" "$REAL.demo"
  mv "$KEEP" "$REAL"
  open -a "$APP"
  echo "config real de volta; a da demonstração ficou em $REAL.demo"
  ;;
*) echo "uso: $0 up|down" >&2; exit 1 ;;
esac
