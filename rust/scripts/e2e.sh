#!/bin/bash
# Roteiro ponta a ponta do app novo (US-501): compila o egeon-app e o `egeon`
# do Rust, sobe o app com EGEON_HOME e HOME numa pasta temporária, cria nós
# pelas rotas, confere os comandos pelo `egeon` novo e derruba tudo.
#
#   rust/scripts/e2e.sh [--no-build] [--keep]
#
# --no-build  usa os binários que já estão em CARGO_TARGET_DIR
# --keep      não apaga a pasta temporária no fim (para olhar o app.log)
#
# Cada passo imprime `ok`, `FALHOU` ou `PULADO <motivo>`. Passo que depende de
# rota que o core ainda não tem sai como PULADO e passa a rodar sozinho quando
# a rota aparecer; o código de saída é 1 só se algo FALHOU.
#
# Isolamento: nada aqui toca ~/.egeon, ~/.claude* nem o /Applications. O app
# roda com EGEON_HOME e HOME numa pasta de /tmp, e só se encerra o que este
# roteiro subiu (pelo pid que ele guardou), nunca por nome.
#
# Os dois agentes (etapa 5, scripts/e2e_agents.sh, do dispatch):
#   E2E_AGENTS=1                 liga a etapa; com `claude` de verdade pede
#                                ANTHROPIC_API_KEY (o HOME é temporário: o
#                                ~/.claude* real nunca é visto)
#   E2E_AGENTS=1 E2E_FAKE_CLAUDE=1   troca o `claude` por um falso que fala o
#                                protocolo de ganchos: sem rede nem chave

set -u

BUILD=1
KEEP=0
for arg in "$@"; do
    case "$arg" in
        --no-build) BUILD=0 ;;
        --keep) KEEP=1 ;;
        -h | --help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "opção desconhecida: $arg" >&2
            exit 2
            ;;
    esac
done

RUST_DIR=$(cd "$(dirname "$0")/.." && pwd)
TARGET=${CARGO_TARGET_DIR:-$RUST_DIR/target/e2e}
case "$TARGET" in /*) ;; *) TARGET=$RUST_DIR/$TARGET ;; esac
BIN=$TARGET/debug
REAL_HOME=$HOME

PASSED=0
FAILED=0
SKIPPED=0
APP_PID=""
TERMINALS=""   # "id:pid" dos nós criados
SEED=$((RANDOM % 9000 + 1000))

ok() { PASSED=$((PASSED + 1)); printf 'ok       %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf 'FALHOU   %s\n' "$1"; [ -n "${2:-}" ] && printf '         %s\n' "$2"; }
skip() { SKIPPED=$((SKIPPED + 1)); printf 'PULADO   %s (%s)\n' "$1" "$2"; }

check() { # check <nome> <comando...>
    local name=$1
    shift
    local out
    if out=$("$@" 2>&1); then ok "$name"; else fail "$name" "$out"; fi
}

# --- ambiente isolado --------------------------------------------------------

# Curto de propósito: o caminho do socket tem de caber em 104 bytes.
T=$(mktemp -d /tmp/egXXXXXX) || { echo "sem pasta temporária" >&2; exit 2; }
mkdir -p "$T/h" "$T/home"
SOCK=$T/h/sock

# Variáveis que fariam o app ou o `claude` enxergar o ambiente real.
for var in $(env | sed -n 's/^\(CLAUDE[A-Za-z_]*\)=.*/\1/p'); do unset "$var"; done
unset EGEON_NODE EGEON_DECK EGEON_TARGET EGEON_FLAVOR ZDOTDIR
export EGEON_HOME=$T/h
export HOME=$T/home
# Sem o ~/.egeon/bin do Egeon estável: o `egeon` dos nós tem de ser o novo.
CLEAN_PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -x -e "$REAL_HOME/.egeon/bin" -e "$REAL_HOME/.egeon-next/bin" | paste -sd: -)
export PATH=$BIN:$CLEAN_PATH

if [ "$HOME" = "$REAL_HOME" ] || [ "${EGEON_HOME#/tmp/eg}" = "$EGEON_HOME" ]; then
    echo "ambiente não isolado; abortando" >&2
    exit 2
fi

# --- encerramento ------------------------------------------------------------

alive() { kill -0 "$1" 2>/dev/null; }
not_alive() { ! alive "$1"; }

cleanup() {
    trap - EXIT
    shutdown_app
    if [ "$KEEP" = 1 ]; then
        echo "pasta mantida: $T"
    else
        case "$T" in /tmp/eg??????) rm -rf "$T" ;; esac
    fi
}

# Fecha o stdin do app (é o que o faz encerrar, como a UI morta) e espera; só
# então, e só no pid que subiu daqui, TERM e KILL.
shutdown_app() {
    [ -n "$APP_PID" ] || return 0
    exec 9>&-
    local i
    for i in $(seq 1 150); do
        alive "$APP_PID" || break
        sleep 0.1
    done
    if alive "$APP_PID"; then
        kill -TERM "$APP_PID" 2>/dev/null
        sleep 2
        alive "$APP_PID" && kill -KILL "$APP_PID" 2>/dev/null
        APP_EXIT=killed
    else
        wait "$APP_PID" 2>/dev/null
        APP_EXIT=$?
    fi
    APP_PID=""
}
# O `exit` é o que interrompe o roteiro: o trap sozinho deixaria ele seguir.
trap cleanup EXIT
trap 'exit 130' INT TERM

# --- ajudantes de HTTP e JSON ------------------------------------------------

STATUS=""
BODY=""
api() { # api <método> <caminho> [corpo]
    local method=$1 path=$2 body=${3:-}
    if [ -n "$body" ]; then
        STATUS=$(curl -s -o "$T/body" -w '%{http_code}' --max-time 10 --unix-socket "$SOCK" \
            -X "$method" --data-binary "$body" "http://localhost$path")
    else
        STATUS=$(curl -s -o "$T/body" -w '%{http_code}' --max-time 10 --unix-socket "$SOCK" \
            -X "$method" "http://localhost$path")
    fi
    BODY=$(cat "$T/body" 2>/dev/null)
}

# A rota ainda não vale quando o core responde com a lista de rotas dele (404)
# ou com "ainda não portada" (501).
route_missing() {
    [ "$STATUS" = 501 ] && return 0
    [ "$STATUS" = 404 ] && printf '%s' "$BODY" | grep -q 'use GET /about'
}

jget() { # jget <campo> — lê JSON do stdin
    python3 -c 'import sys, json
d = json.load(sys.stdin)
v = d.get(sys.argv[1])
print("" if v is None else v)' "$1"
}

until_ok() { # until_ok <segundos> <comando...>
    local limit=$1
    shift
    local end=$((SECONDS + limit))
    while [ "$SECONDS" -lt "$end" ]; do
        "$@" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    return 1
}

# --- 1. build ----------------------------------------------------------------

if [ "$BUILD" = 1 ]; then
    # O cargo e o rustup moram no HOME de verdade; só o app roda no HOME temporário.
    if (cd "$RUST_DIR" && HOME=$REAL_HOME CARGO_TARGET_DIR=$TARGET cargo build -p egeon-app -p egeon-cli >"$T/build.log" 2>&1); then
        ok "compila egeon-app e egeon (CARGO_TARGET_DIR=${TARGET#"$RUST_DIR"/})"
    else
        fail "compila egeon-app e egeon" "$(tail -15 "$T/build.log")"
        exit 1
    fi
fi
for binary in egeon-app egeon; do
    [ -x "$BIN/$binary" ] || { fail "binário $binary em $BIN"; exit 1; }
done

# --- 2. sobe o app -----------------------------------------------------------

mkfifo "$T/in"
exec 9<>"$T/in"
# `9<&-`: o app não herda o lado de escrita, senão o EOF nunca chegaria.
"$BIN/egeon-app" --exit-with-stdin <"$T/in" >"$T/app.log" 2>&1 9<&- &
APP_PID=$!

if until_ok 15 test -S "$SOCK"; then ok "app escuta em \$EGEON_HOME/sock"; else
    fail "app escuta em \$EGEON_HOME/sock" "$(cat "$T/app.log")"
    exit 1
fi

api GET /about
if [ "$STATUS" = 200 ] && [ "$(printf '%s' "$BODY" | jget ok)" = True ]; then
    ok "GET /about (versão $(printf '%s' "$BODY" | jget version))"
else
    fail "GET /about" "status $STATUS: $BODY"
fi

# --- 3. terminal solto e bancada com dois nós -------------------------------

ui() { python3 "$RUST_DIR/scripts/e2e_ui.py" "$SOCK" "$1"; } # canal /ui: um comando
jfield() { python3 -c 'import sys, json; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1"; }

peek_has() { # peek_has <id> <texto>
    api GET "/peek?id=$1&lines=40"
    printf '%s' "$BODY" | grep -q -- "$2"
}

# Terminal solto (POST /terminal): sem endereço de bancada, só o pty.
api POST /terminal "{\"cwd\":\"$HOME\"}"
LOOSE_ID=$(printf '%s' "$BODY" | jget id)
LOOSE_PID=$(printf '%s' "$BODY" | jget pid)
if [ "$STATUS" = 200 ] && [ -n "$LOOSE_ID" ]; then
    TERMINALS="$LOOSE_ID:$LOOSE_PID"
    ok "POST /terminal abre um terminal solto ($LOOSE_ID)"
else
    fail "POST /terminal abre um terminal solto" "status $STATUS: $BODY"
    exit 1
fi

# A conta evita casar com o eco do que foi digitado: `e2e-$((40+2))` aparece
# na linha de comando, e só a saída do shell traz `e2e-42`.
api POST "/terminal/$LOOSE_ID/input" "echo e2e-\$((40+2))-$SEED
"
if [ "$STATUS" = 200 ] && until_ok 10 peek_has "$LOOSE_ID" "e2e-42-$SEED"; then
    ok "input pela rota e saída no /peek"
else
    fail "input pela rota e saída no /peek" "status $STATUS: $(printf '%s' "$BODY" | head -c 400)"
fi

# A bancada e os nós pelo canal /ui, como a UI faz.
mkdir -p "$HOME/proj"
BENCH=$(ui "{\"cmd\":\"create_workbench\",\"path\":\"$HOME/proj\",\"name\":\"e2e\"}" | jfield workbench)
if [ -n "$BENCH" ]; then ok "create_workbench pelo /ui (bancada e2e, id $BENCH)"; else
    fail "create_workbench pelo /ui"
    exit 1
fi
NODE_A=$(ui "{\"cmd\":\"create_node\",\"workbench\":\"$BENCH\",\"type\":\"shell\"}" | jfield node)
NODE_B=$(ui "{\"cmd\":\"create_node\",\"workbench\":\"$BENCH\",\"type\":\"shell\"}" | jfield node)
if [ -n "$NODE_A" ] && [ -n "$NODE_B" ] && [ "$NODE_A" != "$NODE_B" ]; then
    ok "create_node pelo /ui, duas vezes ($NODE_A e $NODE_B)"
else
    fail "create_node pelo /ui, duas vezes" "A=$NODE_A B=$NODE_B"
    exit 1
fi
ui "{\"cmd\":\"link\",\"workbench\":\"$BENCH\",\"from\":\"$NODE_A\",\"to\":\"$NODE_B\",\"both\":true}" >/dev/null &&
    ok "link entre $NODE_A e $NODE_B (nos dois sentidos)" || fail "link entre os nós"

ID_A=$BENCH.$NODE_A
ID_B=$BENCH.$NODE_B
ADDR_A=e2e/$NODE_A
ADDR_B=e2e/$NODE_B

three_alive() {
    [ "$(curl -s --unix-socket "$SOCK" http://localhost/terminals |
        python3 -c 'import sys, json; print(sum(t["alive"] for t in json.load(sys.stdin)["terminals"]))')" = 3 ]
}
if until_ok 10 three_alive; then
    ok "GET /terminals lista o solto e os dois nós, vivos"
else
    fail "GET /terminals lista o solto e os dois nós, vivos" "$(curl -s --unix-socket "$SOCK" http://localhost/terminals)"
fi
for pair in $(curl -s --unix-socket "$SOCK" http://localhost/terminals | python3 -c 'import sys, json
for t in json.load(sys.stdin)["terminals"]:
    print("%s:%s" % (t["id"], t["pid"]))'); do
    case " $TERMINALS " in *" $pair "*) ;; *) TERMINALS="$TERMINALS $pair" ;; esac
done

# --- 4. o `egeon` novo, de fora e de dentro de um terminal ------------------

until_ok 10 peek_has "$ID_A" '%' # o prompt do nó
api POST "/terminal/$ID_A/input" "echo e2e-peek-\$((40+2))-$SEED
"
until_ok 10 peek_has "$ID_A" "e2e-peek-42-$SEED"
EGEON_OUT=$("$BIN/egeon" peek "$ADDR_A" 40 2>&1)
if printf '%s' "$EGEON_OUT" | grep -q "e2e-peek-42-$SEED"; then
    ok "egeon peek $ADDR_A mostra a saída do nó"
else
    fail "egeon peek $ADDR_A" "$EGEON_OUT"
fi

# `peers`, `status`, `trace` e `send` precisam saber quem chama: o app o
# descobre pelo pid do outro lado do socket, então rodam de dentro do nó.
run_in_node() { # run_in_node <id> <nome> <comando...>; saída em $T/<nome>.out e .rc
    local id=$1 name=$2
    shift 2
    api POST "/terminal/$id/input" "$* >$T/$name.out 2>&1; echo \$? >$T/$name.rc; echo fim-\$((20+1))-$name-$SEED
"
    until_ok 15 peek_has "$id" "fim-21-$name-$SEED" && [ "$(cat "$T/$name.rc" 2>/dev/null)" = 0 ]
}

# O core instala uma cópia do `egeon` em $EGEON_HOME/bin e a põe na frente do
# PATH dos nós: tem de ser essa, e igual ao binário novo (não o do estável).
if run_in_node "$ID_A" which "command -v egeon" && [ "$(cat "$T/which.out")" = "$EGEON_HOME/bin/egeon" ] &&
    cmp -s "$EGEON_HOME/bin/egeon" "$BIN/egeon"; then
    ok "dentro do nó, o egeon é a cópia do novo (\$EGEON_HOME/bin/egeon)"
else
    fail "dentro do nó, o egeon é a cópia do novo" "$(cat "$T/which.out" 2>/dev/null)"
fi

if run_in_node "$ID_A" peers egeon peers && grep -q "$ADDR_B" "$T/peers.out"; then
    ok "egeon peers (de $ADDR_A) lista $ADDR_B"
else
    fail "egeon peers (de $ADDR_A) lista $ADDR_B" "$(cat "$T/peers.out" 2>/dev/null)"
fi

if run_in_node "$ID_A" status egeon status && grep -q "\"address\":\"$ADDR_A\"" "$T/status.out"; then
    ok "egeon status (de $ADDR_A) diz o próprio endereço"
else
    fail "egeon status (de $ADDR_A) diz o próprio endereço" "$(cat "$T/status.out" 2>/dev/null)"
fi

if run_in_node "$ID_A" trace "echo e2e-trilha-$SEED | egeon trace" && grep -q "$ADDR_A" "$T/trace.out"; then
    ok "egeon trace (de $ADDR_A) grava na trilha da bancada"
else
    fail "egeon trace (de $ADDR_A)" "$(cat "$T/trace.out" 2>/dev/null)"
fi
TRACE_FILE=$EGEON_HOME/workbenches/$BENCH/trace.md
if grep -q "e2e-trilha-$SEED" "$TRACE_FILE" 2>/dev/null; then
    ok "o texto está em workbenches/$BENCH/trace.md"
else
    fail "o texto está em workbenches/$BENCH/trace.md" "$TRACE_FILE"
fi

# Um shell quieto está livre depois de ~1 s de silêncio e a mensagem tem de
# chegar a ele (o drain do dispatcher), sem ninguém tocar no teclado.
if run_in_node "$ID_A" send "echo e2e-msg-$SEED | egeon send $ADDR_B" &&
    grep -q "enfileirado para $ADDR_B" "$T/send.out"; then
    ok "egeon send de $ADDR_A é aceito para $ADDR_B"
else
    fail "egeon send de $ADDR_A é aceito para $ADDR_B" "$(cat "$T/send.out" 2>/dev/null)"
fi
if until_ok 5 peek_has "$ID_B" "e2e-msg-$SEED"; then
    ok "a mensagem é entregue ao nó quieto $ADDR_B em até 5 s"
else
    fail "a mensagem é entregue ao nó quieto $ADDR_B em até 5 s" "$(printf '%s' "$BODY" | head -c 300)"
fi

if run_in_node "$ID_A" bench "egeon bench"; then
    fail "egeon bench é recusado fora do maestro" "o nó $ADDR_A não é maestro e conseguiu"
elif grep -qi "maestro" "$T/bench.out" 2>/dev/null; then
    ok "egeon bench é recusado fora do maestro"
else
    fail "egeon bench é recusado fora do maestro" "$(cat "$T/bench.out" 2>/dev/null)"
fi

# --- 5. dois agentes claude de verdade --------------------------------------

# O roteiro dos agentes é do dispatch (e2e_agents.sh): sobe um segundo app com
# bancada de verdade e confere o `egeon send` entre dois `claude`.
if [ -f "$RUST_DIR/scripts/e2e_agents.sh" ]; then
    # shellcheck source=/dev/null
    . "$RUST_DIR/scripts/e2e_agents.sh"
else
    skip "dois agentes claude trocando egeon send" "falta scripts/e2e_agents.sh"
fi

# --- 6. encerramento: nada fica de pé --------------------------------------

# Um trabalho em segundo plano num grupo próprio: o HUP no grupo do shell não o
# alcança, só a morte em árvore.
BG_MARK="sleep 7$SEED"
# No nó A: o B acabou de receber a mensagem, que fica digitada na linha dele
# até o Enter, e o comando se misturaria com ela.
api POST "/terminal/$ID_A/input" "$BG_MARK &
"
sleep 0.5
BG_PIDS=$(pgrep -f "^$BG_MARK\$" || true)
if [ -n "$BG_PIDS" ]; then ok "trabalho em segundo plano rodando no nó $ID_A"; else
    api GET "/peek?id=$ID_A&lines=12"
    fail "trabalho em segundo plano rodando no nó $ID_A" "$(printf '%s' "$BODY" | head -c 500)"
fi

shutdown_app
if [ "${APP_EXIT:-}" = 0 ]; then ok "app encerra sozinho quando o stdin fecha (saída 0)"; else
    fail "app encerra sozinho quando o stdin fecha" "saída: ${APP_EXIT:-?}; $(tail -5 "$T/app.log")"
fi

LEFT=""
for pair in $TERMINALS; do
    pid=${pair#*:}
    if ! until_ok 8 not_alive "$pid"; then
        LEFT="$LEFT $pid"
        # Só o que ainda é o shell que o app subiu: pid de quem saiu pode ser
        # reaproveitado. Órfão (ppid 1), zsh e com a pasta dentro da nossa.
        if [ "$(ps -o ppid= -p "$pid" | tr -d ' ')" = 1 ] &&
            ps -o command= -p "$pid" | grep -q 'zsh' &&
            lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | grep -q "^n$T"; then
            kill -KILL "$pid" 2>/dev/null
        fi
    fi
done
for pid in $BG_PIDS; do
    sleep 1
    if alive "$pid"; then
        LEFT="$LEFT $pid"
        # Só o processo que este roteiro subiu, conferido pelo comando.
        ps -o command= -p "$pid" | grep -q "^$BG_MARK\$" && kill -KILL "$pid" 2>/dev/null
    fi
done
if [ -z "$LEFT" ]; then ok "shells e trabalhos dos nós morreram com o app"; else
    fail "shells e trabalhos dos nós morreram com o app" "sobraram:$LEFT"
fi

if [ ! -S "$SOCK" ]; then ok "socket removido no encerramento"; else fail "socket removido no encerramento"; fi

printf '\n%d ok, %d falhou, %d pulado\n' "$PASSED" "$FAILED" "$SKIPPED"
[ "$FAILED" = 0 ]
