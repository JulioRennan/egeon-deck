import Foundation

/// Preset de canvas: quantos nós, de que tipo, onde, com qual agente e qual url
/// base. Nasce de um canvas montado ("salvar como template"), não de edição de
/// arquivo.
///
/// Guarda o caminho do projeto e o caminho que cada nó usa — mas o do projeto
/// como valor inicial, e o dos nós como `cwd` relativo a ele.
///
/// É essa combinação que faz o template servir para worktree: criar a sessão já
/// vem com a pasta preenchida, e apontar para outro checkout reaproveita todos
/// os `cwd` sem edição, porque `deck-backend` resolve em qualquer um deles.
struct Template: Codable {
    var nodes: [NodeConfig]
    /// Pasta do projeto, usada como valor inicial ao criar a sessão. Trocável no
    /// diálogo, o que é o caminho para a segunda worktree.
    var basePath: String?

    /// Em que modo a sessão abre, e com que proporções se for mosaico. Faz parte
    /// da montagem tanto quanto a posição dos nós: um preset de "editor mais
    /// quatro agentes" nasce torto se abrir no canvas quando foi desenhado em
    /// mosaico.
    var view: ViewMode?
    var mosaic: MosaicLayout?

    /// Instancia os nós para uma sessão nova.
    ///
    /// A url dos nós web é reduzida à origem ao salvar, então aqui não há rota
    /// de outra sessão para herdar.
    ///
    /// A conversa é zerada de novo, embora `capture` já não a guarde: templates
    /// salvos por uma versão anterior têm o `sessionId` do molde dentro, e sem
    /// isto continuariam ressuscitando a conversa alheia a cada sessão nova.
    func instantiate() -> [NodeConfig] { nodes.map(\.withoutConversation) }
}

enum TemplateStore {
    static let configURL = URL(fileURLWithPath:
        Flavor.current.config("templates.json").path)

    static func load() -> [String: Template] {
        guard let data = try? Data(contentsOf: configURL),
              let map = try? JSONDecoder().decode([String: Template].self, from: data)
        else { return [:] }
        return map
    }

    /// Ordem estável: a de um dicionário muda a cada execução, e o menu de
    /// templates ficaria se embaralhando sozinho.
    static var names: [String] { load().keys.sorted() }

    static func save(_ map: [String: Template]) {
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(map).write(to: configURL)
    }

    static func template(named name: String) -> Template? { load()[name] }

    static func put(_ template: Template, named name: String) {
        var map = load()
        map[name] = template
        save(map)
        Log.write("template \"\(name)\" salvo com \(template.nodes.count) nós")
    }

    static func remove(named name: String) {
        var map = load()
        map[name] = nil
        save(map)
    }

    // MARK: - Captura

    /// Monta um template a partir dos nós de uma sessão.
    ///
    /// Guarda tudo que define a montagem — tipos, layout, agente, `cwd`, pasta do
    /// projeto — e descarta o que é estado da sessão que serviu de molde: a rota
    /// em que o nó web estava, da qual sobra a origem, e a conversa de cada
    /// agente.
    ///
    /// A conversa é o que mais dói se escapar: o template guardava o `sessionId`
    /// junto, e aí toda sessão criada dele subia com `--resume` na MESMA conversa
    /// do molde — o agente aparecia no meio do assunto de outra sessão, sem o
    /// papel novo, e duas sessões diferentes escreviam na mesma conversa. Um
    /// molde não carrega o que foi dito dentro dele.
    static func capture(from session: SessionConfig) -> Template {
        var nodes = session.nodes
        for i in nodes.indices {
            if nodes[i].type == .web { nodes[i].url = nodes[i].url.flatMap(baseURL(of:)) }
            nodes[i] = nodes[i].withoutConversation
        }
        return Template(nodes: nodes, basePath: session.path,
                        view: session.view, mosaic: session.mosaic)
    }

    /// `http://localhost:3000/farms/123` → `http://localhost:3000`.
    ///
    /// Um preset que reabrisse a rota exata carregaria o estado de navegação de
    /// outra sessão, que é justamente o que ninguém quer herdar.
    static func baseURL(of raw: String) -> String? {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme,
              let host = components.host else { return raw }
        var base = "\(scheme)://\(host)"
        if let port = components.port { base += ":\(port)" }
        return base
    }
}
