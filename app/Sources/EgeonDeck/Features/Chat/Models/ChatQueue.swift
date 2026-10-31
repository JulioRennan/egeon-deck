import Foundation

/// Uma fila de prompts como a coluna do chat a mostra: o nó e o que resumir dele.
struct ChatQueue: Equatable {
    let id: String
    let pending: Int
    /// O agente perguntou numa tarefa e espera você.
    let asking: Bool
    /// Com quem está a tarefa em andamento.
    let workingWith: String?

    init(id: String, queue: PromptQueue) {
        self.id = id
        pending = queue.pendingCount
        asking = queue.items.contains(where: \.awaiting)
        workingWith = queue.inFlight?.sentTo
    }

    /// A largura do painel ao lado da conversa: a que você arrastou ou, sem isso,
    /// bastante para a lista. Nos dois casos sem espremer a thread: em janela
    /// estreita ela é quem manda, e a escolha volta quando a janela crescer.
    static func panelWidth(content: CGFloat, preferred: CGFloat? = nil) -> CGFloat {
        max(minPanel, min(preferred ?? max(420, content * 0.42), content - minThread))
    }

    static let minPanel: CGFloat = 300
    static let minThread: CGFloat = 400

    /// A pergunta vem antes de tudo: é a única coisa aqui que espera você.
    var summary: String {
        if asking { return "? pergunta" }
        let count = pending == 1 ? "1 pendente" : "\(pending) pendentes"
        if let workingWith { return pending == 0 ? "com \(workingWith)" : "\(count) · com \(workingWith)" }
        return pending == 0 ? "nada pendente" : count
    }
}
