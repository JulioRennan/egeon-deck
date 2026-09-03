import Foundation

// MARK: - Requisição

/// Formato aceito pelo socket de controle. `comments` alimenta o fluxo de
/// review; `text` cobre task/raw.
struct DispatchComment: Codable {
    var line: Int?
    var quote: String?
    var body: String
}

struct DispatchRequest: Codable {
    var target: String              // "deck/claude-1"
    var kind: String?               // "review" | "task" | "raw"
    var file: String?
    var text: String?
    var comments: [DispatchComment]?
    /// Sobrepõe o modo do perfil: "bracketed-paste" ou "plain".
    /// Existe porque shell e TUI de agente reagem diferente ao mesmo texto.
    var inject: String?

    /// Quem mandou, quando quem mandou é outro terminal. Ausente = veio de você,
    /// pela extensão ou pelo socket.
    ///
    /// Muda três coisas: exige uma aresta ligando os dois, conta na cadeia de
    /// visitas, e faz a entrega vir com o cabeçalho de quem mandou.
    var from: String?

    /// Prefixa TODAS as linhas do trecho citado.
    ///
    /// A seleção do usuário pode atravessar vários parágrafos. Marcando só a
    /// primeira linha, as demais ficam soltas no prompt e o agente não consegue
    /// dizer onde a citação termina e o comentário começa.
    private static func quoted(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "  > \($0)" }
            .joined(separator: "\n")
    }

    /// A marca de tudo o que o APP põe num prompt — mensagem entre agentes,
    /// review, task. Uma tag só, a mesma dos marcadores de fim de turno
    /// (`[[ED:ok]]`/`[[ED:ask]]`): quem lê o terminal reconhece de onde veio
    /// sem decorar dois vocabulários (ADR-055).
    static let tag = "[ED]"

    private static func indented(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    \($0)" }
            .joined(separator: "\n")
    }

    /// Envelope de mensagem entre agentes: só o cabeçalho com o remetente.
    ///
    /// Mesma forma do envelope de review, e pelo mesmo motivo: sem cabeçalho
    /// explícito o agente confunde o pedido com conteúdo a escrever. Não há
    /// rodapé de "isso não autoriza nada" (ADR-038): o nó tem autonomia para
    /// decidir o que fazer com a mensagem; restrição é coisa da ferramenta do
    /// usuário (permissões do CLI), não do texto que o app injeta.
    private func agentEnvelope(from sender: String, text: String) -> String {
        """
        \(Self.tag) mensagem de \(sender)

        \(text)
        """
    }

    /// Monta o prompt final. Cabeçalho explícito com arquivo, trecho citado e
    /// instrução de fechar o ciclo — sem isso o agente confunde o pedido com
    /// conteúdo a escrever.
    func buildPrompt() -> String? {
        if let from, !from.isEmpty {
            guard let text, !text.isEmpty else { return nil }
            return agentEnvelope(from: from, text: text)
        }
        switch kind ?? "raw" {
        case "review":
            guard let comments, !comments.isEmpty else { return nil }
            var out = "\(Self.tag) review de \(file ?? "arquivo")\n\n"
            for comment in comments {
                let anchor = comment.line.map { "L\($0)" } ?? "—"
                if let quote = comment.quote, !quote.isEmpty {
                    out += "\(anchor)\n\(Self.quoted(quote))\n\n\(Self.indented(comment.body))\n\n"
                } else {
                    out += "\(anchor)\n\(Self.indented(comment.body))\n\n"
                }
            }
            out += "Reescreva o arquivo endereçando cada ponto. "
                + "Ao terminar, anote em uma linha o que mudou."
            return out

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
