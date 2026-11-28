#!/bin/bash
# Etapa 5 do e2e (dono: dispatch): dois agentes `claude` de verdade numa
# bancada, trocando `egeon send` pelo `egeon` do Rust, com o gancho `Stop` e o
# marcador `[[ED:ok]]` decidindo o fim do turno.
#
#   . rust/scripts/e2e_agents.sh        carregado pelo e2e.sh (usa os ajudantes dele)
#   rust/scripts/e2e_agents.sh          sozinho: monta o próprio ambiente
#
# Liga com E2E_AGENTS=1 e pede ANTHROPIC_API_KEY: o `claude` roda com HOME
# temporário e nunca enxerga o ~/.claude* real, então não há login para usar.
# Sem chave, sai PULADO.
#
# E2E_FAKE_CLAUDE=1 troca o `claude` pelo e2e_fake_claude.py: sem modelo e sem
# chave, confere o resto — a linha de comando, os ganchos e o `egeon send` de
# dentro do nó.
#
# Sobe um SEGUNDO egeon-app, com EGEON_HOME próprio: os terminais soltos do
# `POST /terminal` não têm endereço, e o dispatch só enxerga nós de bancada.
# E2E_AGENTS_TIMEOUT (segundos, padrão 240) é quanto esperar cada passo do
# modelo.

# --- sozinho: o ambiente e os ajudantes que o e2e.sh daria ------------------

if ! declare -F ok >/dev/null 2>&1; then
    set -u
    RUST_DIR=$(cd "$(dirname "$0")/.." && pwd)
    TARGET=${CARGO_TARGET_DIR:-$RUST_DIR/target/e2e}
    case "$TARGET" in /*) ;; *) TARGET=$RUST_DIR/$TARGET ;; esac
    BIN=$TARGET/debug
    REAL_HOME=$HOME
    PASSED=0 FAILED=0 SKIPPED=0
    SEED=$((RANDOM % 9000 + 1000))
    ok() { PASSED=$((PASSED + 1)); printf 'ok       %s\n' "$1"; }
    fail() { FAILED=$((FAILED + 1)); printf 'FALHOU   %s\n' "$1"; [ -n "${2:-}" ] && printf '         %s\n' "$2"; }
    skip() { SKIPPED=$((SKIPPED + 1)); printf 'PULADO   %s (%s)\n' "$1" "$2"; }
    until_ok() {
        local limit=$1
        shift
        local end=$((SECONDS + limit))
        while [ "$SECONDS" -lt "$end" ]; do
            "$@" >/dev/null 2>&1 && return 0
            sleep 0.2
        done
        return 1
    }
    # Curto: o caminho do socket tem de caber em 104 bytes.
    T=$(mktemp -d /tmp/egaXXXXXX) || exit 2
    mkdir -p "$T/home"
    for var in $(env | sed -n 's/^\(CLAUDE[A-Za-z_]*\)=.*/\1/p'); do unset "$var"; done
    unset EGEON_NODE EGEON_DECK EGEON_TARGET EGEON_FLAVOR ZDOTDIR
    export HOME=$T/home
    CLEAN_PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -x -e "$REAL_HOME/.egeon/bin" -e "$REAL_HOME/.egeon-next/bin" | paste -sd: -)
    export PATH=$BIN:$CLEAN_PATH
    E2E_AGENTS_ALONE=1
    if [ "${E2E_AGENTS:-0}" = 1 ] && [ "${NO_BUILD:-0}" != 1 ]; then
        (cd "$RUST_DIR" && HOME=$REAL_HOME CARGO_TARGET_DIR=$TARGET cargo build -p egeon-app -p egeon-cli >"$T/build.log" 2>&1) ||
            { fail "compila egeon-app e egeon" "$(tail -15 "$T/build.log")"; exit 1; }
    fi
fi

# --- a etapa -----------------------------------------------------------------

AG_NAME="dois agentes claude trocando egeon send"
AG_HOME=$T/ag
AG_SOCK=$AG_HOME/sock
AG_PROJ=$T/agproj
AG_BENCH=e2e0a9e7
AG_PID=""
AG_WAIT=${E2E_AGENTS_TIMEOUT:-240}

ag_api() { # ag_api <método> <caminho> [corpo] → $AG_STATUS e $AG_BODY
    local body=${3:-}
    AG_STATUS=$(curl -s -o "$T/ag.body" -w '%{http_code}' --max-time 10 --unix-socket "$AG_SOCK" \
        -X "$1" ${body:+--data-binary "$body"} "http://localhost$2")
    AG_BODY=$(cat "$T/ag.body" 2>/dev/null)
}

ag_peek_has() { # ag_peek_has <nó> <texto> — pelo id do terminal, que o /peek já aceita
    ag_api GET "/peek?id=$AG_BENCH.$1&lines=200"
    printf '%s' "$AG_BODY" | grep -q -- "$2"
}

ag_log_has() { grep -q -- "$1" "$T/ag.log"; }

ag_start() {
    mkfifo "$T/ag.in" 2>/dev/null
    exec 8<>"$T/ag.in"
    EGEON_HOME=$AG_HOME "$BIN/egeon-app" --exit-with-stdin <"$T/ag.in" >>"$T/ag.log" 2>&1 8<&- &
    AG_PID=$!
    until_ok 15 test -S "$AG_SOCK"
}

ag_stop() {
    [ -n "$AG_PID" ] || return 0
    # Fechar o stdin é o encerramento limpo: o app derruba os terminais dele.
    exec 8>&-
    local end=$((SECONDS + 10))
    while kill -0 "$AG_PID" 2>/dev/null && [ "$SECONDS" -lt "$end" ]; do sleep 0.2; done
    kill "$AG_PID" 2>/dev/null
    wait "$AG_PID" 2>/dev/null
    AG_PID=""
    rm -f "$T/ag.in"
}

agents_step() {
    if [ "${E2E_AGENTS:-0}" != 1 ]; then
        skip "$AG_NAME" "E2E_AGENTS=1 liga; gasta chave de API"
        return
    fi
    AG_FAKE=${E2E_FAKE_CLAUDE:-0}
    if [ "$AG_FAKE" = 1 ]; then
        AG_NAME="$AG_NAME (claude de mentira)"
    elif [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        skip "$AG_NAME" "falta ANTHROPIC_API_KEY — o claude não usa o login do ~/.claude* real"
        return
    fi
    if [ "$AG_FAKE" != 1 ] && ! command -v claude >/dev/null 2>&1; then
        skip "$AG_NAME" "falta o comando claude"
        return
    fi
    mkdir -p "$AG_HOME" "$AG_PROJ"

    # O agents.json de fábrica sai da primeira subida; o `claude` ganha
    # permissão para o `egeon` (o -p não pergunta, e a TUI pararia no diálogo).
    if ! ag_start; then
        fail "$AG_NAME" "o segundo app não subiu: $(tail -5 "$T/ag.log")"
        return
    fi
    ag_stop
    # O comando do perfil vira linha de shell sem aspas: o parêntese do
    # `Bash(...)` tem de ir já entre aspas, senão o zsh o lê como glob.
    local binary=claude
    [ "$AG_FAKE" = 1 ] && binary=$RUST_DIR/scripts/e2e_fake_claude.py
    python3 - "$AG_HOME/agents.json" "$binary" <<'PY' || { fail "$AG_NAME" "agents.json de fábrica ilegível"; return; }
import json, sys
path, binary = sys.argv[1:]
profiles = json.load(open(path))
profiles["claude"]["command"] = [binary, "--allowedTools", "'Bash(egeon:*)'"]
# Sem som de atenção: o app do e2e usa o notificador de verdade, e uma pergunta
# ou falha do agente tocaria na máquina de quem roda o roteiro.
profiles["claude"].setdefault("attention", {})["sound"] = None
json.dump(profiles, open(path, "w"), indent=2)
PY

    # Papel de cada um: o que fazer quando a mensagem chegar.
    python3 - "$AG_HOME/workbenches.json" "$AG_PROJ" "$AG_BENCH" "$SEED" <<'PY'
import json, sys
path, project, bench, seed = sys.argv[1:]
role_a = ("Você é o nó a de um teste automático. Quando o usuário pedir, rode exatamente "
          f"`echo e2e-agente-{seed} | egeon send b` no Bash e encerre o turno com [[ED:ok]]. "
          "Quando b responder, apenas encerre o turno com [[ED:ok]].")
role_b = ("Você é o nó b de um teste automático. Quando chegar uma mensagem de e2e/a, rode "
          f"exatamente `echo recebido-{seed} | egeon send a` no Bash e encerre o turno com [[ED:ok]].")
nodes = [
    {"type": "agent", "id": "a", "agent": "claude", "model": "haiku", "prompt": role_a},
    {"type": "agent", "id": "b", "agent": "claude", "model": "haiku", "prompt": role_b},
]
edges = [{"from": "a", "to": "b"}, {"from": "b", "to": "a"}]
json.dump([{"id": bench, "name": "e2e", "path": project, "nodes": nodes, "edges": edges,
            "tabOrder": 0, "tabActive": True}], open(path, "w"))
PY

    # O claude de HOME vazio pararia no tema, na chave e na confiança da pasta.
    # A guarda vem antes da escrita: este é o arquivo que nunca pode ser o real.
    case "$HOME" in
        "$T"/*) ;;
        *)
            fail "$AG_NAME" "ambiente não isolado: HOME=$HOME fora de $T — nada foi escrito"
            ag_stop
            return
            ;;
    esac
    python3 - "$HOME/.claude.json" "$AG_PROJ" <<'PY'
import json, os, sys
path, project = sys.argv[1:]
key = os.environ.get("ANTHROPIC_API_KEY", "")
try:
    data = json.load(open(path))
except Exception:
    data = {}
data["hasCompletedOnboarding"] = True
data.setdefault("customApiKeyResponses", {"approved": [], "rejected": []})
if key:
    data["customApiKeyResponses"].setdefault("approved", []).append(key[-20:])
projects = data.setdefault("projects", {})
projects[os.path.realpath(project)] = {"hasTrustDialogAccepted": True, "allowedTools": []}
json.dump(data, open(path, "w"))
PY

    if ! ag_start; then
        fail "$AG_NAME" "o segundo app não subiu: $(tail -5 "$T/ag.log")"
        return
    fi
    # O registro no Dispatcher sai no tique seguinte à subida dos terminais.
    ag_both() { ag_api GET /targets && printf '%s' "$AG_BODY" | grep -q 'e2e/a' && printf '%s' "$AG_BODY" | grep -q 'e2e/b'; }
    if ! until_ok 10 ag_both; then
        fail "$AG_NAME" "a bancada não registrou os dois: $AG_BODY"
        ag_stop
        return
    fi
    ag_api GET /terminals
    if printf '%s' "$AG_BODY" | grep -q -- '--allowedTools' && printf '%s' "$AG_BODY" | grep -q -- '--settings'; then
        ok "os nós sobem o claude com --allowedTools e os ganchos (--settings)"
    else
        fail "os nós sobem o claude com --allowedTools e os ganchos" "$AG_BODY"
    fi
    if until_ok 90 ag_log_has 'gancho\[e2e/a\]: start' && until_ok 30 ag_log_has 'gancho\[e2e/b\]: start'; then
        ok "os dois claude sobem com os ganchos (SessionStart)"
    else
        fail "os dois claude sobem com os ganchos (SessionStart)" "$(grep -E 'terminal e2e|gancho' "$T/ag.log" | tail -5)"
    fi

    ag_api POST "/message?target=e2e/a" "Comece o teste."
    if [ "$AG_STATUS" = 200 ]; then ok "a tarefa entra na fila de e2e/a (/message)"; else
        fail "a tarefa entra na fila de e2e/a (/message)" "status $AG_STATUS: $AG_BODY"
    fi

    if until_ok "$AG_WAIT" ag_log_has 'cadeia\[e2e/a → e2e/b\]' && until_ok 60 ag_peek_has b "e2e-agente-$SEED"; then
        ok "o claude de a manda a b por egeon send (envelope e token na tela de b)"
    else
        fail "o claude de a manda a b por egeon send" "$(grep -E 'cadeia|dispatch\[|gancho' "$T/ag.log" | tail -8)"
    fi
    if until_ok 30 ag_log_has 'atenção\[e2e/a\]: aguardando e2e/b'; then
        ok "o fim do turno de a fica aguardando b (vizinho pendente vence o [[ED:ok]])"
    else
        fail "o fim do turno de a fica aguardando b" "$(grep -E 'gancho|atenção' "$T/ag.log" | tail -6)"
    fi
    if until_ok "$AG_WAIT" ag_log_has 'cadeia\[e2e/b → e2e/a\]'; then
        ok "o claude de b responde a a (cadeia e2e/a → e2e/b → e2e/a)"
    else
        fail "o claude de b responde a a" "$(grep -E 'cadeia|gancho' "$T/ag.log" | tail -8)"
    fi
    # A volta de b abre turno novo em a; o fim dele é "terminou", pelo marcador.
    if until_ok "$AG_WAIT" ag_log_has 'atenção\[e2e/a\]: terminou — por gancho Stop, ok no'; then
        ok "a volta de b fecha o turno de a: gancho Stop e [[ED:ok]] dizem terminou"
    else
        fail "o gancho Stop e o marcador" "$(grep -E 'gancho|atenção' "$T/ag.log" | tail -8)"
    fi
    ag_stop
}

agents_step

if [ "${E2E_AGENTS_ALONE:-0}" = 1 ]; then
    printf '\n%s ok · %s falhou · %s pulado — %s\n' "$PASSED" "$FAILED" "$SKIPPED" "$T"
    [ "${KEEP:-0}" = 1 ] || rm -rf "$T"
    [ "$FAILED" = 0 ]
fi
