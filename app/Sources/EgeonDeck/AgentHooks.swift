import Foundation

/// Faz o CLI do agente avisar qual conversa está aberta.
///
/// Sem isso o app só conhece a conversa que ele mesmo criou: um `/resume`,
/// `/clear` ou fork feito por você dentro da TUI é invisível, e o arranque
/// seguinte retoma a conversa antiga, desfazendo sua escolha.
///
/// O gancho é `UserPromptSubmit`, e não `SessionStart`, de propósito: dispara a
/// cada prompt, então o app se corrige sozinho no turno seguinte mesmo que uma
/// transição escape. Custa um curl em socket local por prompt.
///
/// O arquivo de settings é nosso e vai por `--settings`. Nada é escrito no
/// `~/.claude/settings.json` do usuário — a config dele não é lugar para o app
/// mexer.
enum AgentHooks {
    static var directory: URL { Flavor.current.configDirectory }
    static var settingsFile: URL { directory.appendingPathComponent("claude-hooks.json") }
    static var script: URL { directory.appendingPathComponent("report-session.sh") }

    /// Variável de ambiente que diz ao script de qual terminal ele está falando.
    static let targetVariable = "EGEON_TARGET"

    /// Escrito no arranque, como o `worktree-copy.sh`: é um arquivo feito para ser
    /// lido e ajustado, e para isso precisa existir antes de alguém precisar dele.
    static func install() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            try scriptBody.write(to: script, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            try settingsBody.write(to: settingsFile, atomically: true, encoding: .utf8)
        } catch {
            Log.write("hooks: não consegui escrever em \(directory.path) — \(error)")
        }
    }

    /// Três regras do `UserPromptSubmit` que este script tem de respeitar, e as
    /// três mordem se ignoradas:
    ///
    /// - o **stdout entra no contexto do prompt**. Uma linha solta aqui vira texto
    ///   que o agente lê em toda mensagem sua
    /// - **exit 2 apaga o prompt** que você acabou de escrever. Sair diferente de
    ///   zero por qualquer motivo é inaceitável num gancho que só reporta
    /// - o hook **roda síncrono e bloqueia** o prompt. Com o app fora do ar, um
    ///   curl sem `--max-time` deixaria você esperando
    private static var scriptBody: String {
        """
        #!/usr/bin/env bash
        # Egeon Deck — avisa ao app qual conversa este terminal está usando.
        #
        # Gancho UserPromptSubmit do Claude Code. NÃO escreva em stdout: ali o texto
        # entra no contexto do prompt. E sempre saia com 0: exit 2 apaga o prompt do
        # usuário, e qualquer outro código mostra um aviso na tela dele.
        set -u

        payload=$(cat)
        [ -n "${EGEON_TARGET:-}" ] || exit 0

        id=$(printf '%s' "$payload" | /usr/bin/python3 -c \\
          'import sys,json;print(json.load(sys.stdin).get("session_id",""))' 2>/dev/null)
        [ -n "$id" ] || exit 0

        # --max-time porque o hook bloqueia o prompt: app fora do ar não pode te
        # fazer esperar. Saída descartada pelo motivo acima.
        curl -s -o /dev/null --max-time 1 --unix-socket "\(ControlSocket.path)" \\
          -X POST "http://eg/session?target=$EGEON_TARGET&id=$id" 2>/dev/null

        exit 0
        """
    }

    private static var settingsBody: String {
        """
        {
          "hooks": {
            "UserPromptSubmit": [
              {
                "hooks": [
                  {
                    "type": "command",
                    "command": "\(script.path)",
                    "timeout": 5
                  }
                ]
              }
            ]
          }
        }
        """
    }
}
