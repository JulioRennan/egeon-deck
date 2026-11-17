import Foundation

/// Pedido de permissão do time chegando ao maestro que aprova (ADR-080): quem
/// recebe o aviso, o que o aviso diz e o que ele pode responder.
enum MaestroPermissions {
    /// Só permissão de ferramenta. A pergunta do `AskUserQuestion` passa pelo
    /// mesmo gancho, mas é a VOCÊ que o agente pergunta.
    static func delegable(_ ask: PermissionAsk) -> Bool {
        ask.tool != "AskUserQuestion"
    }

    /// O maestro da bancada que aprova pelo time, quando há um e o pedido não
    /// é dele — aprovar o próprio pedido seria não ter pedido.
    static func approver(for ask: PermissionAsk, in bench: WorkbenchConfig) -> NodeConfig? {
        guard delegable(ask), ask.address.hasPrefix(bench.name + "/") else { return nil }
        return bench.nodes.first {
            $0.approvesTeamPermissions && "\(bench.name)/\($0.id)" != ask.address
        }
    }

    /// O que o maestro lê. UMA linha, curta: texto longo ou de várias linhas
    /// entra no Claude Code como "colado", e o modelo — com razão — não age
    /// sobre colado sem você confirmar; medido, ele parava para perguntar. Tem
    /// o id e os comandos prontos porque o pedido expira junto com o gancho.
    static func notice(for ask: PermissionAsk) -> String {
        let who = ask.address.split(separator: "/").last.map(String.init) ?? ask.address
        let what = oneLine(ask.summary, max: 140)
        let why = ask.detail.map { oneLine($0, max: 80) }.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
        let always = ask.canAlwaysAllow ? " (ou --always)" : ""
        return "[ED] pedido de permissão de \(who) — \(ask.tool): \(what)\(why) — "
            + "responda: egeon allow \(ask.id)\(always) · egeon deny \(ask.id)"
    }

    private static func oneLine(_ text: String, max: Int) -> String {
        let flat = text.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > max ? String(flat.prefix(max - 1)) + "…" : flat
    }

    /// Como o pedido aparece em `egeon permissions`.
    static func listing(_ ask: PermissionAsk) -> [String: Any] {
        var out: [String: Any] = ["id": ask.id, "from": ask.address, "tool": ask.tool,
                                  "summary": ask.summary, "always": ask.canAlwaysAllow]
        if let detail = ask.detail { out["detail"] = detail }
        return out
    }
}
