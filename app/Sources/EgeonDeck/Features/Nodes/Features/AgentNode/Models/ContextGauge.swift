import Foundation

/// Quanto da janela de contexto do modelo está em uso.
struct ContextGauge: Equatable {
    let used: Int
    let window: Int

    /// `[1m]` é pedido explícito da janela grande e não aparece no transcript,
    /// que grava só o id. Uso acima da janela do catálogo é o CLI usando a
    /// grande sem ninguém ter pedido, o que alguns planos fazem sozinhos.
    init?(tokens: Int, requested: String?, model: ModelCatalog.Model?) {
        let large = 1_000_000
        let asked = requested?.lowercased().contains("[1m]") == true ? large : model?.contextWindow
        guard let asked, asked > 0 else { return nil }
        used = tokens
        window = tokens > asked ? max(asked, large) : asked
    }

    var fraction: Double { min(1, Double(used) / Double(window)) }

    /// Para cima: dizer "0%" com a conversa já ocupando algo seria mentira, e
    /// "100%" só quando a janela encheu de fato é o que o arredondamento garante.
    var usedPercent: Int { min(100, Int((fraction * 100).rounded(.up))) }

    /// Do verde (120°) ao vermelho (0°), passando pelo amarelo na metade.
    var hue: Double { 120 * (1 - fraction) }

    var text: String { "\(usedPercent)%" }

    var detail: String { "\(Self.short(used)) de \(Self.short(window)) em uso" }

    static func short(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let value = Double(tokens) / 1_000_000
            return value == value.rounded() ? "\(Int(value))M" : String(format: "%.1fM", value)
        }
        return tokens >= 1000 ? "\(tokens / 1000)K" : "\(tokens)"
    }
}
