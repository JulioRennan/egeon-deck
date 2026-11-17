import Foundation

/// As regras que vão no fim do system prompt de um agente: as da bancada mais as
/// do terminal, na ordem (ADR-056).
///
/// O texto é seu — o app não reescreve regra nenhuma. O que ele põe é a moldura:
/// de onde cada bloco veio, e a linha de precedência. Essa linha não é zelo:
/// medindo adesão, uma diretriz geral em conflito com uma restrição específica
/// costuma ser resolvida a favor da ação, e dizer qual vale fecha essa porta.
enum AgentRules {
    /// O bloco pronto, ou nil quando não há regra nenhuma dos dois lados.
    static func block(workbench: String?, node: String?) -> String? {
        let fromWorkbench = clean(workbench)
        let fromNode = clean(node)
        guard fromWorkbench != nil || fromNode != nil else { return nil }

        var out = [header]
        // Com um bloco só, dizer de onde ele veio não informa nada que o agente
        // possa usar — ele não escolhe entre os dois, segue os dois.
        if let fromWorkbench, let fromNode {
            out.append("Da bancada:\n\(fromWorkbench)")
            out.append("Deste terminal:\n\(fromNode)")
        } else if let only = fromWorkbench ?? fromNode {
            out.append(only)
        }
        return out.joined(separator: "\n\n")
    }

    static let header = "Regras — valem sobre o papel acima. Quando um pedido "
        + "conflitar com uma delas, siga a regra e diga por quê."

    private static func clean(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
