import Foundation

/// O aviso que vai para a central de notificações do macOS quando um terminal
/// para — "precisa de você" ou "terminou" — com o app fora da frente.
///
/// Só as duas paradas: segundo plano e "aguardando vizinho" voltam sozinhos, e
/// avisar deles é chamar você para nada.
struct SystemNotice: Equatable {
    let workbench: String
    let node: String
    let title: String
    let body: String
    /// Um por terminal: aviso novo do mesmo terminal substitui o anterior em vez
    /// de empilhar.
    var identifier: String { "egeon.\(workbench)/\(node)" }

    /// `nil` para o que não avisa. `detail` é o que está esperando você — o
    /// comando da permissão, a pergunta — quando se sabe.
    init?(address: String, activity: Activity, detail: String? = nil) {
        guard let slash = address.lastIndex(of: "/") else { return nil }
        let headline: String
        switch activity {
        case .asking:  headline = "precisa de você"
        case .waiting: headline = "já terminou o serviço"
        default:       return nil
        }
        workbench = String(address[..<slash])
        node = String(address[address.index(after: slash)...])
        title = "A bancada \(workbench) \(headline)"
        // O terminal vai no corpo: no título ele competia com a bancada, que é
        // o que você reconhece de relance.
        let extra = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        body = extra.isEmpty ? node : "\(node): \(Self.clip(extra))"
    }

    private static func clip(_ text: String, limit: Int = 180) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
