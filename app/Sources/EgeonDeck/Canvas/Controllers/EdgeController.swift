import AppKit

/// O controller das ligações de uma bancada: recebe os gestos do canvas — criar,
/// remover, ciclar, limitar — e a rota `/edge`, aplica a regra no
/// `WorkbenchConfig` e devolve o resultado para a tela.
///
/// Não é dono de estado nenhum: o `workbenches.json` continua com um dono só, e o
/// controller lê e escreve por closures. Canvas idem — resolvido na hora, porque a
/// rota `/edge` vale para bancada que nem tem shell na tela.
final class EdgeController {
    private let canvas: () -> CanvasContainer?
    private let config: () -> WorkbenchConfig?
    private let change: ((inout WorkbenchConfig) -> Void) -> Void
    private let persist: () -> Void

    init(canvas: @escaping () -> CanvasContainer?,
         config: @escaping () -> WorkbenchConfig?,
         change: @escaping ((inout WorkbenchConfig) -> Void) -> Void,
         persist: @escaping () -> Void) {
        self.canvas = canvas
        self.config = config
        self.change = change
        self.persist = persist
    }

    /// Assume os callbacks de aresta do canvas e entrega as arestas atuais.
    /// Chamado a cada fiação do shell — reconstruir a bancada refaz isto.
    func wire() {
        guard let canvas = canvas() else { return }
        canvas.onCreateEdge = { [weak self] edge in self?.add(edge) }
        canvas.onRemoveEdge = { [weak self] link in self?.remove(link) }
        canvas.onEditEdgeLimit = { [weak self] link in self?.editLimit(link) }
        canvas.onCycleEdgeDirection = { [weak self] link in self?.cycleDirection(link) }
        canvas.edges = config()?.edgeList ?? []
    }

    func add(_ edge: EdgeConfig) {
        guard let cfg = config() else { return }
        var edges = cfg.edgeList
        guard !edges.contains(edge),
              !edges.contains(EdgeConfig(from: edge.to, to: edge.from)) else { return }
        edges.append(edge)
        edges.append(EdgeConfig(from: edge.to, to: edge.from))
        change { $0.edges = edges }
        canvas()?.edges = edges
        persist()

        Log.write("aresta[\(cfg.name)]: \(edge.from) ↔ \(edge.to)")

        // Ciclo é legítimo — revisor e implementador são exatamente isso — mas
        // não pode ser silencioso: é ele que faz duas máquinas conversarem sem
        // você no meio.
        // Par conversando é o padrão agora, e `maxSends` é quem segura ele: avisar
        // em toda ligação criada transformaria o banner em ruído, e ruído não avisa
        // nada. O que ainda merece aviso é o ciclo que só o teto da bancada segura —
        // três nós ou mais, onde cada seta dispara uma vez e nenhum contador de
        // seta chega perto (ADR-012).
        if let cycle = Self.cycle(through: edge, in: edges), cycle.count - 1 >= 3 {
            let limit = cfg.visitLimit
            let canvas = canvas()
            canvas?.showBanner("Ciclo: \(cycle.joined(separator: " → ")) — "
                               + "cada terminal entra \(limit)× na mesma cadeia, depois recusa")
            Log.write("aresta[\(cfg.name)]: ciclo \(cycle.joined(separator: " → ")), "
                      + "limite de \(limit) visitas")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak canvas] in
                canvas?.showBanner(nil)
            }
        }
    }

    /// Remove a ligação inteira, os dois sentidos. Na tela é uma linha só, e tirar
    /// metade do que se vê seria mais confuso que tirar tudo — para ficar com um
    /// sentido só existe o botão de direção ao lado.
    func remove(_ link: EdgeLink) {
        guard let cfg = config() else { return }
        let edges = cfg.edgeList.filter {
            EdgeLink.pair($0.from, $0.to) != (link.a, link.b)
        }
        change { $0.edges = edges }
        canvas()?.edges = edges
        persist()
        Log.write("aresta[\(cfg.name)]: removida \(link.a) ↔ \(link.b)")
    }

    /// Quantas idas e voltas esta ligação permite.
    ///
    /// Vazio = sem limite próprio, sobra o teto da bancada. O diálogo diz isso na
    /// cara porque "vazio" e "zero" são coisas opostas aqui, e errar entre os
    /// dois é a diferença entre liberar e travar.
    func editLimit(_ link: EdgeLink) {
        guard let cfg = config() else { return }
        let current = link.maxSends

        let alert = NSAlert()
        alert.messageText = link.isBidirectional
            ? "\(link.a) ↔ \(link.b)"
            : (link.aToB ? "\(link.a) → \(link.b)" : "\(link.b) → \(link.a)")
        alert.informativeText = "Quantas vezes esta ligação pode disparar numa mesma conversa. "
            + "Num par ligado nos dois sentidos, é o número de idas e voltas.\n\n"
            + "Vazio = sem limite próprio; vale só o teto da bancada "
            + "(\(cfg.visitLimit) visitas por terminal)."
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.stringValue = current.map(String.init) ?? ""
        field.placeholderString = "sem limite"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = typed.isEmpty ? nil : Int(typed)
        // Texto que não é número vira nada em vez de virar "sem limite": você
        // digitou algo, e interpretar isso como "libera" é o erro mais caro
        // possível nesse campo.
        if !typed.isEmpty, limit == nil { return }

        // Grava nos dois sentidos: na tela é uma linha, e um número que valesse só
        // para a ida deixaria a volta com o valor antigo sem nada dizendo isso.
        var updated = link
        updated.maxSends = limit.map { max(1, $0) }
        replace(updated)
        canvas()?.edges = config()?.edgeList ?? []
        Log.write("aresta[\(cfg.name)]: \(link.a) ↔ \(link.b) "
                  + "limite \(limit.map(String.init) ?? "nenhum")")
    }

    /// Troca a direção da ligação: ida → ida e volta → volta, e de volta ao começo.
    func cycleDirection(_ link: EdgeLink) {
        guard let cfg = config() else { return }
        let next = link.cycled()
        replace(next)
        canvas()?.edges = config()?.edgeList ?? []
        let sentido = next.isBidirectional ? "↔" : (next.aToB ? "→" : "←")
        Log.write("aresta[\(cfg.name)]: \(link.a) \(sentido) \(link.b)")
    }

    /// A rota `/edge` por dentro: cria a ligação se ela não existe, e aponta,
    /// inverte ou cicla a que existe.
    ///
    /// Direção vazia é o caminho do arrasto: cria como o gesto cria, com o padrão da
    /// casa. É o que faz a rota servir para verificar o próprio padrão, em vez de só
    /// o que ela mesma manda.
    func apply(from: String, to: String, direction: String) -> [String: Any] {
        guard let cfg = config() else { return ["ok": false, "error": "bancada desconhecida"] }
        let ids = Set(cfg.nodes.map(\.id))
        guard ids.contains(from), ids.contains(to), from != to else {
            return ["ok": false, "error": "nó desconhecido ou igual: '\(from)' / '\(to)'"]
        }
        let (a, b) = EdgeLink.pair(from, to)
        let existente = EdgeLink.collapse(cfg.edgeList)
            .first { $0.a == a && $0.b == b }

        var alvo: EdgeLink
        switch direction {
        case "":
            // Vazio é o caminho do gesto quando não há nada: `add` cria com o
            // padrão da casa, e é o que faz esta rota verificar o próprio padrão em
            // vez de só o que ela manda. Existindo, vazio é CONSULTA — forçar
            // bidirecional aqui faria uma leitura mudar o que ela mede.
            if let existente { return Self.edgePayload(existente, a: a, b: b) }
            add(EdgeConfig(from: from, to: to))
            return Self.edgePayload(EdgeLink.collapse(config()?.edgeList ?? [])
                                        .first { $0.a == a && $0.b == b }, a: a, b: b)
        case "<->", "both":
            alvo = EdgeLink(a: a, b: b, aToB: true, bToA: true,
                            maxSends: existente?.maxSends ?? EdgeConfig.defaultSends)
        case "->":
            alvo = EdgeLink(a: a, b: b, aToB: from == a, bToA: from != a,
                            maxSends: existente?.maxSends ?? EdgeConfig.defaultSends)
        case "<-":
            alvo = EdgeLink(a: a, b: b, aToB: from != a, bToA: from == a,
                            maxSends: existente?.maxSends ?? EdgeConfig.defaultSends)
        case "none":
            // O que o X da linha faz. Está aqui pelo mesmo motivo que o resto da
            // rota: sem desfazer, verificar a criação de fora deixa lixo na bancada.
            guard let existente else {
                return ["ok": true, "a": a, "b": b, "direction": "none", "edges": []]
            }
            remove(existente)
            return ["ok": true, "a": a, "b": b, "direction": "none", "edges": []]
        case "cycle":
            guard let existente else {
                return ["ok": false, "error": "não há ligação entre '\(a)' e '\(b)' para ciclar"]
            }
            alvo = existente.cycled()
        default:
            return ["ok": false, "error": "direction desconhecida '\(direction)'; "
                    + "use ->, <-, <->, cycle ou none"]
        }

        replace(alvo)
        canvas()?.edges = config()?.edgeList ?? []
        let sentido = alvo.isBidirectional ? "↔" : (alvo.aToB ? "→" : "←")
        Log.write("aresta[\(cfg.name)]: \(a) \(sentido) \(b) (por /edge)")
        return Self.edgePayload(alvo, a: a, b: b)
    }

    private static func edgePayload(_ link: EdgeLink?, a: String, b: String) -> [String: Any] {
        guard let link else { return ["ok": false, "error": "ligação \(a)/\(b) não existe"] }
        return ["ok": true, "a": a, "b": b,
                "direction": link.isBidirectional ? "<->" : (link.aToB ? "->" : "<-"),
                "maxSends": link.maxSends ?? NSNull(),
                "edges": link.edges.map { "\($0.from)→\($0.to)" }]
    }

    /// Reescreve as arestas de um par com o que a ligação diz agora.
    ///
    /// Na posição da primeira que existia, e não no fim da lista: o `workbenches.json`
    /// é lido à mão, e uma ligação que salta para o fim do arquivo a cada clique
    /// embaralharia o arquivo sem nada ter mudado de fato.
    private func replace(_ link: EdgeLink) {
        change { cfg in
            let others = cfg.edgeList.filter {
                EdgeLink.pair($0.from, $0.to) != (link.a, link.b)
            }
            let position = cfg.edgeList.firstIndex {
                EdgeLink.pair($0.from, $0.to) == (link.a, link.b)
            } ?? others.count
            var edges = others
            edges.insert(contentsOf: link.edges, at: min(position, edges.count))
            cfg.edges = edges
        }
        persist()
    }

    /// Caminho de volta de `edge.to` até `edge.from`, se existir — ou seja, o
    /// ciclo que esta aresta acabou de fechar. Busca em largura: o ciclo mais
    /// curto é o que descreve melhor o que foi criado.
    static func cycle(through edge: EdgeConfig, in edges: [EdgeConfig]) -> [String]? {
        var queue: [[String]] = [[edge.to]]
        var seen: Set<String> = [edge.to]
        while let path = queue.first {
            queue.removeFirst()
            let last = path[path.count - 1]
            if last == edge.from { return path + [edge.to] }
            for next in edges.filter({ $0.from == last }).map(\.to) where !seen.contains(next) {
                seen.insert(next)
                queue.append(path + [next])
            }
        }
        return nil
    }
}
