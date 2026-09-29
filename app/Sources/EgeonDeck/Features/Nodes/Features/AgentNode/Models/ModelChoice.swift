/// O que se trocou no seletor do cabeçalho de um agente. Modelo e esforço
/// andam juntos porque o efeito é o mesmo — o processo reinicia e a conversa
/// fica — e dividir o caminho em dois duplicaria cada elo até o AppDelegate.
enum ModelChoice: Equatable {
    /// Nil é o padrão do CLI.
    case model(String?)
    /// Nil é o padrão do CLI.
    case effort(String?)

    /// O nó com a escolha aplicada.
    func applied(to node: NodeConfig) -> NodeConfig {
        var copy = node
        switch self {
        case .model(let value): copy.model = value
        case .effort(let value): copy.effort = value
        }
        return copy
    }
}
