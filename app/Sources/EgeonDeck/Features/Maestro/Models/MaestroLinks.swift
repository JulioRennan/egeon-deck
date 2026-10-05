import Foundation

/// As ligações do maestro, que não se desenham (ADR-066).
///
/// O maestro é o mestre da bancada: alcança todo terminal dela, e todo agente
/// o alcança de volta — é por onde chega a resposta de quem ele acionou
/// (ADR-058). Desenhadas, seriam N setas saindo de um card só, cobrindo as
/// ligações que importam ler: as de trabalho entre os outros. O canvas mostra
/// `edges`; as guardas e o `egeon peers` leem `effective`.
enum MaestroLinks {
    /// As arestas da bancada mais as implícitas do maestro. Uma aresta
    /// desenhada entre o maestro e alguém vence a implícita — é como se dá a
    /// ela um `maxSends` próprio.
    ///
    /// A implícita não tem limite por seta (`maxSends` nil): o maestro
    /// conversa com cada terminal quantas vezes a orquestração pedir, e o teto
    /// de revisitas da bancada continua sendo a rede contra o laço.
    static func effective(_ bench: WorkbenchConfig) -> [EdgeConfig] {
        var edges = bench.edgeList
        for maestro in bench.nodes where maestro.isMaestro {
            for node in bench.nodes where node.id != maestro.id {
                switch node.type {
                case .agent:
                    add(EdgeConfig(from: maestro.id, to: node.id, maxSends: nil), to: &edges)
                    add(EdgeConfig(from: node.id, to: maestro.id, maxSends: nil), to: &edges)
                case .shell:
                    // Shell não responde: a volta seria uma seta morta.
                    add(EdgeConfig(from: maestro.id, to: node.id, maxSends: nil), to: &edges)
                case .editor, .web:
                    break
                }
            }
        }
        return edges
    }

    private static func add(_ edge: EdgeConfig, to edges: inout [EdgeConfig]) {
        if !edges.contains(edge) { edges.append(edge) }
    }
}
