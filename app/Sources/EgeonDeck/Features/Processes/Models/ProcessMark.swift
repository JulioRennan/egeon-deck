import Foundation

/// A procedência de um processo: o nó que o lançou e o flavor do app (ADR-083).
///
/// Vai no ambiente, e não no nome do processo, porque o ambiente é herdado por
/// tudo que o terminal abre — node, python, o Chrome do Playwright — e continua
/// lá quando o pai morre e o processo vira filho do launchd. É justamente o
/// órfão que precisa dizer de onde veio: pela árvore, ele já não diz.
enum ProcessMark {
    static let node = "EGEON_NODE"
    static let deck = "EGEON_DECK"
    /// Posto pelo launchd em quem ele abre como app, e herdado dali para baixo.
    static let bundleVariable = "__CFBundleIdentifier"
    /// O do estável e o do dev (`.dev` no fim).
    static let bundlePrefix = "dev.duckcoder.egeondeck"

    /// Saem do ambiente herdado antes de marcar. O app lançado de dentro de um
    /// terminal do Egeon (o `install.sh`, o `dev.sh`) herdava o endereço daquele
    /// terminal, e todo shell aberto por ele saía com a procedência errada.
    static let inherited: Set<String> = [node, deck, ClaudeHooks.targetVariable]

    static func stamp(_ environment: inout [String: String], address: String) {
        environment[node] = address
        environment[deck] = Flavor.current.identifier
    }

    /// O nó escrito no ambiente. Processo de antes da marca só tem o
    /// `EGEON_TARGET` dos agentes — ainda serve para dizer de quem é.
    static func node(in environment: [String: String]) -> String? {
        environment[node] ?? environment[ClaudeHooks.targetVariable]
    }
}
