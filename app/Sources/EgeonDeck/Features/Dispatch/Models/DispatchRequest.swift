import Foundation

// MARK: - Requisição

/// Formato aceito pelo socket de controle.
struct DispatchRequest: Codable {
    var target: String              // "deck/claude-1"
    var kind: String?               // "task" | "raw"
    var file: String?
    var text: String?
    /// Sobrepõe o modo do perfil: "bracketed-paste" ou "plain".
    /// Existe porque shell e TUI de agente reagem diferente ao mesmo texto.
    var inject: String?
    /// Imagens que vão anexadas, em caminho absoluto. Cada uma é colada sozinha
    /// antes do texto: o Claude Code só troca caminho de imagem por anexo
    /// (`[Image #1]`) quando o paste é SÓ o caminho — no meio do texto ele
    /// fica texto, e o agente nem a vê.
    var images: [String]?

    /// Quem mandou, quando quem mandou é outro terminal. Ausente = veio de você,
    /// pelo chat ou pelo socket.
    ///
    /// Muda três coisas: exige uma aresta ligando os dois, conta na cadeia de
    /// visitas, e faz a entrega vir com o cabeçalho de quem mandou.
    var from: String?

    /// A marca de tudo o que o APP põe num prompt — mensagem entre agentes,
    /// task. Uma tag só, a mesma dos marcadores de fim de turno
    /// (`[[ED:ok]]`/`[[ED:ask]]`): quem lê o terminal reconhece de onde veio
    /// sem decorar dois vocabulários (ADR-055).
    static let tag = "[ED]"

    /// Envelope de mensagem entre agentes: só o cabeçalho com o remetente.
    ///
    /// Sem cabeçalho explícito o agente confunde o pedido com conteúdo a
    /// escrever. Não há
    /// rodapé de "isso não autoriza nada" (ADR-038): o nó tem autonomia para
    /// decidir o que fazer com a mensagem; restrição é coisa da ferramenta do
    /// usuário (permissões do CLI), não do texto que o app injeta.
    private func agentEnvelope(from sender: String, text: String) -> String {
        """
        \(Self.tag) mensagem de \(sender)

        \(text)
        """
    }

    /// Comando do CLI (`/clear`, `/model sonnet`, `/compact …`): a primeira
    /// palavra é `/nome`, sem outra barra — `/Users/x/a.md` é caminho, não
    /// comando.
    var isSlashCommand: Bool {
        guard let text, text.hasPrefix("/") else { return false }
        let name = text.dropFirst().prefix { !$0.isWhitespace }
        return !name.isEmpty && !name.contains("/")
            && name.first.map { $0.isLetter } == true
    }

    /// O que chega de uma mensagem entre terminais: com envelope para agente,
    /// cru para shell — que não lê cabeçalho, e o executaria como comando
    /// inválido antes do comando de verdade (ADR-066).
    ///
    /// Comando com `/` também vai cru: o CLI só o reconhece no começo do
    /// prompt, e qualquer envelope — em cima ou embaixo — vira argumento dele
    /// (`/model sonnet` + rodapé é um modelo que não existe).
    func message(from sender: String, toShell: Bool) -> String? {
        var copy = self
        let raw = toShell || isSlashCommand
        copy.from = raw ? nil : sender
        if raw { copy.kind = "raw" }
        return copy.buildPrompt()
    }

    /// O aviso que vai antes do comando cru, com o envelope de sempre: sem ele
    /// o comando chega sem remetente, e o agente vê a conversa mudar (modelo,
    /// contexto) sem saber quem mexeu.
    func commandNotice(from sender: String) -> String? {
        guard isSlashCommand, let text else { return nil }
        let command = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
        return agentEnvelope(from: sender, text: """
            Aviso: logo depois desta mensagem chega o comando `\(command)` no seu terminal, \
            mandado por \(sender). Não precisa responder — só encerre o turno.
            """)
    }

    /// Monta o prompt final. Cabeçalho explícito com o arquivo e a instrução —
    /// sem isso o agente confunde o pedido com conteúdo a escrever.
    func buildPrompt() -> String? {
        if let from, !from.isEmpty {
            guard let text, !text.isEmpty else { return nil }
            return agentEnvelope(from: from, text: text)
        }
        switch kind ?? "raw" {
        case "task":
            guard let text, !text.isEmpty else { return nil }
            var out = Self.tag
            if let file { out += " \(file)" }
            return out + "\n\n\(text)\n\nAplique no código."

        default:
            return text?.isEmpty == false ? text : nil
        }
    }
}
