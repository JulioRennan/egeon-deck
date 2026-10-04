import Foundation

/// O comando `egeon`, que o agente usa para descobrir e acionar os vizinhos.
///
/// Existe porque o catálogo de endereços que ia no system prompt congelava a
/// topologia do arranque: aresta criada depois nunca chegava ao agente, e nó com
/// `cmd` trocado não recebia catálogo nenhum. Perguntar em tempo de execução não
/// tem esse problema — e o system prompt fica curto e estável, que é o que o
/// cache de prompt gosta.
///
/// Um script no PATH e não um servidor MCP porque o Egeon não é de um CLI só:
/// isto funciona igual no Claude Code, no Codex, no Gemini e num terminal comum,
/// pela ferramenta de shell que todos já têm. MCP entra depois, por perfil, para
/// quem souber falar.
enum EgeonCLI {
    /// Fora do diretório de config: é o PATH dos processos filhos que aponta para
    /// cá, e um `bin/` deixa claro que ali dentro tudo é executável.
    static var directory: URL { Flavor.current.config("bin") }
    static var executable: URL { directory.appendingPathComponent("egeon") }

    static func install() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try body.write(to: executable, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        } catch {
            Log.write("egeon: não consegui escrever \(executable.path) — \(error)")
        }
    }

    /// O script não recebe nem envia o endereço de quem está chamando.
    ///
    /// É de propósito: quem pergunta é identificado pelo app a partir do processo
    /// do outro lado do socket. Um parâmetro aqui seria só uma sugestão — e as
    /// guardas de cadeia não podem depender de algo que o agente escreve.
    /// Interno e não privado: o que o script oferece é contrato com o agente, e
    /// o teste guarda esse contrato.
    static var body: String {
        """
        #!/usr/bin/env bash
        # Egeon Deck — falar com os outros terminais desta bancada.
        #
        #   egeon peers              quem você pode acionar
        #   egeon send <endereço>    manda o stdin para ele
        #   egeon peek <endereço>    o que ele mostra agora, sem interromper
        #   egeon trace [texto]      registra na trilha da bancada (texto ou stdin)
        #   egeon status             quem você é e como está este terminal
        #
        # Só no terminal maestro (ADR-066) — montar e reconfigurar a bancada:
        #   egeon bench              a bancada: regras, nós, arestas, estado
        #   egeon models             CLIs, modelos e esforços que cada um aceita
        #   egeon plan               valida o plano (JSON no stdin), sem aplicar
        #   egeon apply              valida e aplica o plano (JSON no stdin)
        #   egeon guide              o manual do maestro
        #
        # Você não diz quem você é: o app descobre pelo processo que abriu a
        # conexão. Não adianta passar o endereço de outro terminal.
        set -euo pipefail

        SOCK="\(ControlSocket.path)"

        \(ControlSocket.shellEncoder)
        api() {
            local method="$1" path="$2"
            shift 2
            curl -sS --fail-with-body --unix-socket "$SOCK" -X "$method" \\
                 "http://eg$path" "$@"
        }

        case "${1:-}" in
          peers)
            api GET /peers
            ;;
          send)
            [ $# -ge 2 ] || { echo "uso: egeon send <endereço> (texto no stdin)" >&2; exit 2; }
            # --data-binary @- e não -d: -d come as quebras de linha, e o que vai
            # aqui é texto livre de várias linhas.
            # Codificado: endereço com espaço no nome da bancada quebrava a linha HTTP.
            api POST "/message?target=$(enc "$2")" --data-binary @-
            ;;
          peek)
            [ $# -ge 2 ] || { echo "uso: egeon peek <endereço> [linhas]" >&2; exit 2; }
            # Só de quem você já pode acionar: ler a tela de um terminal com que
            # você não tem aresta seria bisbilhotar fora da topologia.
            api GET "/peek?target=$(enc "$2")${3:+&lines=$3}"
            ;;
          trace)
            # Texto nos argumentos ou no stdin: uma linha cabe na chamada, e o
            # heredoc é para quando vem mais que isso.
            if [ $# -ge 2 ]; then
                shift
                printf '%s' "$*" | api POST /trace --data-binary @-
            else
                api POST /trace --data-binary @-
            fi
            ;;
          status)
            api GET /status
            ;;
          bench)
            api GET /maestro/bench
            ;;
          models)
            api GET /maestro/models
            ;;
          plan)
            api POST "/maestro/apply?dry=1" --data-binary @-
            ;;
          apply)
            api POST /maestro/apply --data-binary @-
            ;;
          guide)
            # Embutido e não pedido ao app: é o mesmo texto da skill, e um CLI
            # sem skill precisa dele mesmo quando o maestro ainda não foi ligado.
            cat <<'EGEON_GUIDE'
        \(MaestroGuide.text)
        EGEON_GUIDE
            ;;
          *)
            sed -n '2,17p' "$0" | cut -c3-
            exit 2
            ;;
        esac
        """
    }
}
