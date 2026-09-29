import Foundation

/// Os modelos que um CLI conhece, com nome de gente e o esforço que cada um
/// aceita. É o que deixa o menu dizer "Opus 5.5" em vez de `opus`, e o slider
/// mostrar só os níveis que o modelo escolhido tem.
///
/// Genérico de propósito: quem sabe montar um é o submódulo do CLI (o Claude
/// Code lê do próprio binário). Sem catálogo, o nó fica com os apelidos e a lista
/// de níveis do perfil, como antes.
struct ModelCatalog: Codable, Equatable {
    struct Model: Codable, Equatable {
        /// O que vai na flag: `claude-opus-5-5`.
        let id: String
        let family: String
        /// `Opus 5.5`.
        let label: String
        /// Níveis aceitos, do menor para o maior. Vazio = o modelo não tem
        /// esforço, e o slider fica desligado.
        let efforts: [String]
        /// O que o CLI usa quando não se passa `--effort` — o "auto".
        let defaultEffort: String?

        /// `claude-opus-5-5` → [5, 5]; `claude-3-5-haiku` → [3, 5]. Data de
        /// snapshot (`20251001`) não é versão.
        var version: [Int] {
            id.split(separator: "-").compactMap { part in
                part.count < 8 ? Int(part) : nil
            }
        }
    }

    let models: [Model]

    /// Ordem do menu: as famílias que se usa no dia a dia primeiro.
    static let familyOrder = ["fable", "opus", "sonnet", "haiku", "mythos"]

    /// Apelidos que o CLI resolve para uma família — `opusplan` planeja com Opus.
    static let aliasFamily = ["opusplan": "opus"]

    private func newestFirst(_ models: [Model]) -> [Model] {
        models.sorted { $1.version.lexicographicallyPrecedes($0.version) }
    }

    private var families: [String] {
        let present = Set(models.map(\.family))
        let known = Self.familyOrder.filter(present.contains)
        return known + present.subtracting(known).sorted()
    }

    /// O mais novo de cada família, na ordem do menu.
    var featured: [Model] {
        families.compactMap { family in newestFirst(models.filter { $0.family == family }).first }
    }

    /// O resto, por família e do mais novo ao mais velho — vai num submenu.
    var older: [Model] {
        let top = Set(featured.map(\.id))
        return families.flatMap { family in
            newestFirst(models.filter { $0.family == family && !top.contains($0.id) })
        }
    }

    /// O modelo por trás do que o nó pediu ou do que o transcript gravou.
    ///
    /// Aceita o id exato, o id com data de snapshot (`claude-haiku-4-5-20251001`)
    /// ou sufixo (`[1m]`), e apelido de família (`opus` → o Opus mais novo, que é
    /// o que o CLI resolve).
    func model(for name: String?) -> Model? {
        guard let raw = name?.lowercased(), !raw.isEmpty else { return nil }
        let name = raw.components(separatedBy: "[").first ?? raw
        if let exact = models.first(where: { $0.id == name }) { return exact }
        if let prefixed = models.filter({ name.hasPrefix($0.id + "-") })
            .max(by: { $0.id.count < $1.id.count }) {
            return prefixed
        }
        let family = Self.aliasFamily[name] ?? name
        return newestFirst(models.filter { $0.family == family }).first
    }

    /// Nome de gente para um id ou apelido; nil quando o catálogo não conhece.
    func label(for name: String?) -> String? { model(for: name)?.label }
}
