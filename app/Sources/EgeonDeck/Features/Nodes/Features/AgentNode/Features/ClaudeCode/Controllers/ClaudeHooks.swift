import Foundation

/// Faz o CLI do agente contar ao app o que acabou de acontecer no terminal.
///
/// Três ganchos, e cada um responde uma pergunta que de fora não tem resposta:
///
/// - `UserPromptSubmit` — qual conversa está aberta. Sem isso o app só conhece a
///   que ele mesmo criou: um `/resume`, `/clear` ou fork feito por você dentro
///   da TUI é invisível, e o arranque seguinte retoma a conversa antiga,
///   desfazendo sua escolha (ADR-014).
/// - `Stop` — o turno acabou. É o instante exato, sem depender de o pty se calar
///   nem de o modelo lembrar de escrever o marcador; e diz se ficou trabalho de
///   fundo rodando, que é fato do CLI e não palavra do modelo (ADR-067).
/// - `Notification` — o CLI está pedindo permissão. Este é o caso que marcador
///   nenhum alcança: o diálogo é desenhado pelo programa, não é mensagem do
///   modelo (ADR-024).
///
/// O `UserPromptSubmit` é a cada prompt de propósito, e não `SessionStart`: o
/// app se corrige sozinho no turno seguinte mesmo que uma transição escape.
/// Custa um curl em socket local por prompt.
///
/// O arquivo de settings é nosso e vai por `--settings`. Nada é escrito no
/// `~/.claude/settings.json` do usuário — a config dele não é lugar para o app
/// mexer.
enum ClaudeHooks {
    static var directory: URL { Flavor.current.configDirectory }
    static var settingsFile: URL { directory.appendingPathComponent("claude-hooks.json") }
    static var script: URL { directory.appendingPathComponent("agent-hook.sh") }

    /// Variável de ambiente que diz ao script que ele está dentro do Egeon. Não
    /// é identidade: quem fala vem do pid da conexão (ADR-040).
    static let targetVariable = "EGEON_TARGET"

    /// Escrito no arranque, como o `worktree-copy.sh`: é um arquivo feito para ser
    /// lido e ajustado, e para isso precisa existir antes de alguém precisar dele.
    static func install() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        // Nome anterior, de quando o gancho só relatava a conversa. Ninguém mais
        // aponta para ele, e deixá-lo no diretório é convidar a editar o arquivo
        // errado.
        try? fm.removeItem(at: directory.appendingPathComponent("report-session.sh"))

        do {
            try scriptBody.write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            try settingsBody.write(to: settingsFile, atomically: true, encoding: .utf8)
        } catch {
            Log.write("hooks: não consegui escrever em \(directory.path) — \(error)")
        }
    }

    /// Um script para os três ganchos, com o evento em `$1`: ler o
    /// `hook_event_name` do payload custaria mais um processo de python em algo
    /// que roda a cada prompt.
    ///
    /// Três regras destes ganchos, e as três mordem se ignoradas:
    ///
    /// - o **stdout do `UserPromptSubmit` entra no contexto do prompt**. Uma
    ///   linha solta aqui vira texto que o agente lê em toda mensagem sua
    /// - **exit 2 apaga o prompt** no `UserPromptSubmit` e **impede o agente de
    ///   parar** no `Stop`. Sair diferente de zero por qualquer motivo é
    ///   inaceitável num gancho que só relata
    /// - o gancho **roda síncrono e segura a TUI**. Com o app fora do ar, um
    ///   curl sem `--max-time` deixaria você esperando
    private static var scriptBody: String {
        """
        #!/usr/bin/env bash
        # Egeon Deck — conta ao app o que acabou de acontecer neste terminal.
        #
        # Ganchos do Claude Code. NÃO escreva em stdout: no UserPromptSubmit o
        # texto entra no contexto do prompt. E sempre saia com 0: exit 2 apaga o
        # prompt do usuário, e no Stop impede o agente de parar.
        set -u

        event="${1:-}"
        # Drenado mesmo quando não é lido: stdin fechado sem leitura devolve
        # SIGPIPE para quem escreveu.
        payload=$(cat)
        # Fora do Egeon (claude aberto num Terminal comum) não há a quem contar.
        # A variável NÃO diz quem somos: o app descobre pelo processo que abriu
        # a conexão, como faz com o `egeon` (ADR-040).
        [ -n "${EGEON_TARGET:-}" ] || exit 0

        # --max-time porque o gancho bloqueia a TUI: app fora do ar não pode te
        # fazer esperar. Saída descartada pelo motivo acima.
        post() {
            curl -s -o /dev/null --max-time 1 --unix-socket "\(ControlSocket.path)" \\
              -X POST "http://eg$1" 2>/dev/null
        }

        case "$event" in
          prompt)
            # O python devolve a query pronta, com os dois campos já escapados.
            #
            # Um processo só porque o gancho roda a cada prompt e bloqueia a TUI. E
            # a query montada lá dentro, e não aqui, porque o `transcript_path`
            # carrega a pasta do usuário: passando pelo shell, um home com espaço
            # viraria dois campos, e no `read` o caminho chegaria cortado.
            q=$(printf '%s' "$payload" | /usr/bin/python3 -c \\
              'import sys,json,urllib.parse as u
        d=json.load(sys.stdin)
        i=d.get("session_id") or ""
        print("" if not i else "id="+u.quote(i)+"&transcript="+u.quote(d.get("transcript_path") or ""))' \\
              2>/dev/null)
            [ -n "$q" ] || exit 0
            post "/conversation?$q"
            ;;
          stop)
            # O transcript vai junto: o histórico do chat lê o turno dele.
            # `bg` é o trabalho de fundo que vai acordar o agente (tarefas mais
            # crons) e `last` o fim da última mensagem, de onde sai o marcador
            # sem esperar o transcript ser gravado (ADR-067). Os dois só vão
            # quando o CLI manda: sem eles o app decide pelo transcript.
            q=$(printf '%s' "$payload" | /usr/bin/python3 -c \\
              'import sys,json,urllib.parse as u
        d=json.load(sys.stdin)
        q="transcript="+u.quote(d.get("transcript_path") or "")
        if "background_tasks" in d or "session_crons" in d:
            q+="&bg="+str(len(d.get("background_tasks") or [])+len(d.get("session_crons") or []))
        m=d.get("last_assistant_message")
        if isinstance(m,str) and m:
            q+="&last="+u.quote(m[-400:],safe="")
        print(q)' 2>/dev/null)
            post "/activity?event=stop&$q"
            ;;
          ask|start)
            post "/activity?event=$event"
            ;;
          permission)
            # Abre o pedido no app e espera a resposta do chat. O diálogo do CLI
            # continua na tela enquanto isto roda, e responder lá também vale:
            # aí o app diz `gone` e o gancho sai sem imprimir nada (ADR-068).
            # Só o que sai no stdout é a decisão, e só quando ela veio daqui.
            printf '%s' "$payload" | /usr/bin/python3 -c \\
              'import sys,json,socket,time
        def call(method,path,body=b""):
            s=socket.socket(socket.AF_UNIX); s.settimeout(3); s.connect(sys.argv[1])
            s.sendall((method+" "+path+" HTTP/1.1\\r\\nHost: eg\\r\\nContent-Length: "+str(len(body))+"\\r\\nConnection: close\\r\\n\\r\\n").encode()+body)
            data=b""
            while True:
                chunk=s.recv(65536)
                if not chunk: break
                data+=chunk
            s.close()
            return json.loads(data.split(b"\\r\\n\\r\\n",1)[1] or b"{}")
        try:
            opened=call("POST","/permission",sys.stdin.buffer.read())
        except Exception:
            sys.exit(0)
        ask=opened.get("id")
        if not ask: sys.exit(0)
        end=time.time()+\(permissionWait)
        while time.time()<end:
            time.sleep(0.4)
            try:
                reply=call("GET","/permission?id="+ask)
            except Exception:
                sys.exit(0)
            state=reply.get("state")
            if state=="answered":
                print(json.dumps(reply.get("output") or {}))
                sys.exit(0)
            if state!="pending": sys.exit(0)' "\(ControlSocket.path)" 2>/dev/null
            ;;
        esac

        exit 0
        """
    }

    /// Só os ganchos. Nada de chave interna do CLI aqui dentro.
    ///
    /// Cheguei a pôr `"ccrRecap": false` para desligar o resumo de "você voltou
    /// depois de um tempo fora", que escreve marcador na tela sem ser resposta a
    /// ninguém. Saiu por duas razões: o recap **não dispara gancho nenhum**
    /// (medido), então quem tem gancho já está protegido pelo `speaksHooks` do
    /// Dispatcher; e chave não documentada num arquivo que sobe em TODO terminal
    /// de agente é risco sem contrapartida — o que este arquivo quebrar, quebra
    /// tudo de uma vez.
    private static var settingsBody: String {
        """
        {
          "hooks": {
            "SessionStart": [
              { "hooks": [{ "type": "command", "command": "\(command("start"))", "timeout": 5 }] }
            ],
            "UserPromptSubmit": [
              { "hooks": [{ "type": "command", "command": "\(command("prompt"))", "timeout": 5 }] }
            ],
            "Stop": [
              { "hooks": [{ "type": "command", "command": "\(command("stop"))", "timeout": 5 }] }
            ],
            "PermissionRequest": [
              { "hooks": [{ "type": "command", "command": "\(command("permission"))", "timeout": \(permissionWait + 20) }] }
            ],
            "Notification": [
              { "matcher": "permission_prompt",
                "hooks": [{ "type": "command", "command": "\(command("ask"))", "timeout": 5 }] }
            ]
          }
        }
        """
    }

    /// Quanto o gancho de permissão espera a resposta do chat. Esgotado, sai
    /// calado e o diálogo do terminal segue sozinho — não é prazo para você,
    /// é o teto de um processo parado.
    static let permissionWait = 580

    /// A linha de comando é interpretada por um shell e o caminho carrega o nome
    /// da pasta do usuário: as aspas não são zelo, são o que faz o gancho
    /// sobreviver a um home com espaço no nome.
    private static func command(_ event: String) -> String {
        "\\\"\(script.path)\\\" \(event)"
    }
}
