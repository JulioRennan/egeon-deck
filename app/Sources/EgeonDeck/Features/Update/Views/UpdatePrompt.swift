import AppKit

/// O aviso de versão nova. Em folha, e não em `runModal`: enquanto ele está
/// aberto, os terminais continuam desenhando e o socket continua respondendo.
enum UpdatePrompt {
    private static let notesLimit = 420

    static func text(version: String, notes: String, agents: Int) -> String {
        var parts: [String] = []
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append(trimmed.count > notesLimit ? String(trimmed.prefix(notesLimit)) + "…" : trimmed)
        }
        if agents > 0 {
            let plural = agents == 1 ? "1 agente aberto" : "\(agents) agentes abertos"
            parts.append("Reiniciar encerra o que estiver rodando: \(plural). As conversas são retomadas quando o app voltar.")
        }
        // O app ainda não tem assinatura da Apple: dizer o que o clique autoriza.
        parts.append("O app não tem assinatura da Apple. Ao atualizar, ele confere a assinatura própria da "
                     + "versão baixada e tira dela a quarentena do macOS.")
        return parts.joined(separator: "\n\n")
    }

    static func show(_ update: AvailableUpdate, agents: Int, auto: Bool, in window: NSWindow,
                     onChoice: @escaping (_ update: Bool, _ auto: Bool) -> Void) {
        guard window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Versão \(update.version) do Egeon Deck disponível"
        alert.informativeText = text(version: update.version, notes: update.notes, agents: agents)
        alert.addButton(withTitle: "Atualizar e reiniciar")
        alert.addButton(withTitle: "Depois")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Atualizar automaticamente: baixar sozinho e trocar quando eu fechar o app"
        alert.suppressionButton?.state = auto ? .on : .off
        alert.beginSheetModal(for: window) { response in
            onChoice(response == .alertFirstButtonReturn, alert.suppressionButton?.state == .on)
        }
    }
}
