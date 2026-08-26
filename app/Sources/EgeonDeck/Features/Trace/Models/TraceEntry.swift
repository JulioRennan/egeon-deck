import Foundation

/// Uma linha da trilha da bancada: um agente dizendo o que fez num turno.
///
/// O texto é do agente (`egeon trace`); o resto é carimbo do app — quem falou
/// vem do pid do socket, nunca do texto (ADR-012), e CLI, modelo e conversa
/// vêm do nó. Assim a trilha diz "o agente X, rodando o Claude Code com o
/// modelo Y na conversa Z, fez tal coisa" sem que o agente possa se passar
/// por outro nem inventar de onde veio.
struct TraceEntry: Equatable {
    let address: String
    /// A bancada de verdade, não o nome: o nome se repete quando você apaga
    /// e recria; o id não.
    let workbenchID: String
    let at: Date
    var cli: String? = nil
    var model: String? = nil
    var conversation: String? = nil
    let text: String

    /// Teto de segurança, não de estilo: o agente é instruído a escrever uma
    /// ou duas linhas, mas um que despeje a resposta inteira não pode
    /// transformar a trilha num transcript.
    static let textLimit = 1500

    init(address: String, workbenchID: String, at: Date, cli: String? = nil, model: String? = nil,
         conversation: String? = nil, text: String) {
        self.address = address
        self.workbenchID = workbenchID
        self.at = at
        self.cli = cli
        self.model = model
        self.conversation = conversation
        self.text = Self.cap(text, limit: Self.textLimit)
    }

    var markdown: String {
        var stamp = [cli, model].compactMap { $0 }
        if let conversation { stamp.append("conversa \(conversation.prefix(8))") }
        // Só o id do nó: a bancada é o arquivo.
        var lines = ["## \(Self.clock.string(from: at)) · \(node)"]
        if !stamp.isEmpty { lines.append(stamp.joined(separator: " · ")) }
        lines.append("")
        lines.append(text.isEmpty ? "—" : text)
        return lines.joined(separator: "\n") + "\n\n"
    }

    var workbench: String {
        address.split(separator: "/", maxSplits: 1).first.map(String.init) ?? address
    }

    var node: String {
        address.split(separator: "/", maxSplits: 1).last.map(String.init) ?? address
    }

    static func cap(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
