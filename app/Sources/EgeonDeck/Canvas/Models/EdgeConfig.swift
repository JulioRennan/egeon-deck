import Foundation

/// Uma ligação dirigida entre dois nós da mesma bancada: `from` pode acionar
/// `to`.
///
/// Sempre de mão única, e ida e volta continuam sendo DUAS: é o que faz o ciclo de
/// dois e o de três serem o mesmo mecanismo, com `maxSends` e autorização
/// raciocinando por sentido (ADR-012). O que mudou é só a tela — o par é desenhado
/// como uma linha só, com ponta nas duas extremidades. Ver `EdgeLink` e ADR-028.
struct EdgeConfig: Codable, Equatable {
    var from: String
    var to: String

    /// Quantas vezes esta seta pode disparar na mesma conversa. Nil = sem limite
    /// próprio, vale só o teto da bancada.
    ///
    /// Num par ligado nos dois sentidos, este é o número de idas e voltas: com 2,
    /// A fala, B responde, A fala, B responde, e a próxima é cortada.
    ///
    /// Só aperta, nunca afrouxa. O teto da bancada continua valendo por cima —
    /// e tem de continuar, porque limite por seta não segura `A→B→C→A`: ali cada
    /// seta dispara uma vez só e o contador nunca chega perto.
    var maxSends: Int? = EdgeConfig.defaultSends

    /// Duas idas e voltas: delega, recebe, ajusta, recebe. É o ciclo útil mais
    /// comum, e o próximo já costuma ser repetição.
    ///
    /// Baixo de propósito. Turno de agente degrada com a quantidade de rodadas
    /// mesmo sobrando contexto — a "inércia conversacional" —, e no
    /// multi-agente 40% das falhas catalogadas pelo MAST são desalinhamento
    /// entre agentes, que só tem mais chance de aparecer a cada volta. Somando
    /// que isto roda enquanto você está longe da máquina, errar para menos custa
    /// uma rodada a mais pedida por você; errar para mais custa tempo e token
    /// sem ninguém olhando.
    static let defaultSends = 2

    /// Igualdade só por origem e destino: é o que identifica a ligação. Duas
    /// arestas entre o mesmo par não existem, e comparar o limite junto faria
    /// `contains` falhar depois de você editar o número.
    static func == (a: EdgeConfig, b: EdgeConfig) -> Bool {
        a.from == b.from && a.to == b.to
    }
}

extension EdgeConfig {
    /// O `Decodable` sintetizado ignora o valor padrão da propriedade: aresta
    /// gravada antes de `maxSends` existir voltaria com nil, ou seja, sem limite
    /// nenhum — o oposto do que o padrão quer dizer.
    ///
    /// Chave ausente e `null` explícito são coisas diferentes aqui: ausente herda
    /// o padrão, `null` desliga o limite desta seta e deixa só o teto da bancada.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(String.self, forKey: .from)
        to = try container.decode(String.self, forKey: .to)
        maxSends = container.contains(.maxSends)
            ? try container.decodeIfPresent(Int.self, forKey: .maxSends)
            : EdgeConfig.defaultSends
    }
}

// MARK: - Ligação (o par visto como uma coisa só)

/// As arestas entre dois nós, colapsadas no que a tela mostra: uma linha com ponta
/// em cada extremidade que tem sentido — `───▶`, `◀───` ou `◀───▶`.
///
/// Existe por dois motivos. O par desenhado como duas curvas precisava de uma
/// faixa própria para cada uma não cobrir a outra, e ainda sobrava um cruzamento;
/// colapsado, o problema deixa de existir em vez de ser contornado. E ler o sentido
/// passa a ser olhar as pontas, sem contar quantas linhas saem de onde.
///
/// Guarda o par em ordem de nome para ter identidade estável — quem é a origem do
/// TRAÇADO é decidido na hora de desenhar, pela posição dos cards, senão uma linha
/// que podia ser reta viraria volta por baixo só por causa do alfabeto.
struct EdgeLink: Equatable {
    let a: String
    let b: String
    /// `a` pode acionar `b`. Na tela, ponta do lado de `b`.
    var aToB: Bool
    /// `b` pode acionar `a`. Na tela, ponta do lado de `a`.
    var bToA: Bool
    /// Limite da ligação. Com os dois sentidos divergindo no arquivo editado à mão,
    /// vale o de `a→b` — a pastilha grava nos dois, porque na tela é uma coisa só.
    var maxSends: Int?

    var isBidirectional: Bool { aToB && bToA }

    /// As arestas reais, que são o que vive no `workbenches.json` e o que as guardas
    /// leem.
    var edges: [EdgeConfig] {
        var out: [EdgeConfig] = []
        if aToB { out.append(EdgeConfig(from: a, to: b, maxSends: maxSends)) }
        if bToA { out.append(EdgeConfig(from: b, to: a, maxSends: maxSends)) }
        return out
    }

    /// Igualdade só pelo par: é o que identifica a linha na tela. Trocar a direção
    /// não faz dela outra ligação — é a mesma linha mudando de estado, e o realce
    /// sob o cursor precisa sobreviver ao clique no botão.
    static func == (x: EdgeLink, y: EdgeLink) -> Bool { x.a == y.a && x.b == y.b }

    /// Próximo estado do botão: ida → ida e volta → volta → ida.
    ///
    /// Nunca passa por "nenhum dos dois": ligação sem sentido nenhum não é uma
    /// linha, é uma linha removida, e para isso existe o X ao lado.
    func cycled() -> EdgeLink {
        var next = self
        switch (aToB, bToA) {
        case (true, false):  next.aToB = true;  next.bToA = true
        case (true, true):   next.aToB = false; next.bToA = true
        default:             next.aToB = true;  next.bToA = false
        }
        return next
    }

    static func pair(_ x: String, _ y: String) -> (a: String, b: String) {
        x <= y ? (x, y) : (y, x)
    }

    /// Colapsa as arestas de uma bancada em ligações, na ordem em que aparecem.
    static func collapse(_ edges: [EdgeConfig]) -> [EdgeLink] {
        var links: [EdgeLink] = []
        for edge in edges {
            let (a, b) = pair(edge.from, edge.to)
            let forward = edge.from == a
            if let index = links.firstIndex(where: { $0.a == a && $0.b == b }) {
                if forward {
                    links[index].aToB = true
                    // O limite do sentido a→b manda quando existe: sem esta regra,
                    // qual dos dois números aparece dependeria da ordem do arquivo.
                    links[index].maxSends = edge.maxSends
                } else {
                    links[index].bToA = true
                    if !links[index].aToB { links[index].maxSends = edge.maxSends }
                }
            } else {
                links.append(EdgeLink(a: a, b: b, aToB: forward, bToA: !forward,
                                      maxSends: edge.maxSends))
            }
        }
        return links
    }
}
