import Foundation

/// Preset de um terminal: o papel que ele cumpre.
///
/// Três camadas, e esta é a do meio:
/// - `agents.json` diz COMO falar com um CLI (bracketed paste, silêncio, resume)
/// - o componente diz O QUE este terminal é (revisor, front, shell de build)
/// - `templates.json` diz o ARRANJO dos nós no canvas
///
/// O componente referencia um perfil de agente; não o substitui.
struct NodeTemplate: Codable {
    /// Nome que virou o id do nó, e por isso aparece no endereço de dispatch:
    /// `deck/revisor`.
    var name: String
    /// `shell` ou `agent`. Editar um nó pode trocar de um para o outro.
    var kind: NodeKind
    /// Relativo à raiz da bancada — nunca absoluto. É o que faz o mesmo
    /// componente valer em qualquer worktree. Não é do CLI: é onde o terminal
    /// abre.
    var cwd: String?
    /// Mensagem entregue ao agente quando ele sobe. Vai pela fila do Dispatcher,
    /// que espera o `warmupMs` do perfil e o silêncio do pty: injetar antes de a
    /// TUI ter leitor de stdin perde o texto.
    var prompt: String?
    /// As regras deste terminal, somadas às da bancada (ADR-056). Um CLI pode
    /// SUBSTITUIR este texto pelo dele em `byAgent` (ADR-057).
    var rules: String?

    /// Com qual CLI este componente nasce. É escolha, não identidade: o mesmo
    /// componente vale em qualquer um.
    var agent: String?

    /// O que muda de um CLI para outro, por chave do `agents.json`.
    ///
    /// O componente é o PAPEL — nome, tipo, pasta, prompt e regras atravessam
    /// qualquer CLI. Comando, configuração e modelo não atravessam nada:
    /// `opus` não existe no OpenCode e `~/.claude-agro` não diz nada ao Codex.
    /// Eles moram aqui, e o componente segue valendo quando você troca de CLI
    /// no meio do caminho (ADR-057).
    var byAgent: [String: Overrides]?

    /// O que um CLI muda no componente.
    struct Overrides: Codable, Equatable {
        /// Comando completo, quando o padrão do perfil não serve.
        var cmd: String?
        /// Pasta de configuração do CLI: com qual conjunto de plugins, MCP,
        /// settings e credenciais este terminal sobe. Absoluto.
        var config: String?
        /// Modelo pedido ao CLI. Nulo é o padrão dele.
        var model: String?
        /// **Substitui** o `rules` da base quando presente — override, e não
        /// soma: quem escreve regra para um CLI está reescrevendo aquele
        /// trecho, não acrescentando ao geral.
        var rules: String?

        var isEmpty: Bool { cmd == nil && config == nil && model == nil && rules == nil }
    }

    /// Os valores efetivos para um CLI: o que vem da base, com o que aquele CLI
    /// substitui.
    struct Resolved {
        var cmd: String?
        var config: String?
        var model: String?
        var rules: String?
    }

    func resolved(for cli: String?) -> Resolved {
        let over = cli.flatMap { byAgent?[$0] }
        return Resolved(cmd: over?.cmd, config: over?.config, model: over?.model,
                        rules: over?.rules ?? rules)
    }

    /// O que este CLI guarda de próprio, para o formulário mostrar ao trocar.
    func overrides(for cli: String?) -> Overrides {
        cli.flatMap { byAgent?[$0] } ?? Overrides()
    }

    init(name: String, kind: NodeKind, agent: String? = nil, cwd: String? = nil,
         prompt: String? = nil, rules: String? = nil, byAgent: [String: Overrides]? = nil) {
        self.name = name
        self.kind = kind
        self.agent = agent
        self.cwd = cwd
        self.prompt = prompt
        self.rules = rules
        self.byAgent = byAgent
    }

    /// Conveniência: o que é de UM CLI já entra no mapa dele.
    init(name: String, kind: NodeKind, agent: String?, cmd: String?, config: String?,
         model: String?, cwd: String?, prompt: String?, rules: String?) {
        let over = Overrides(cmd: cmd, config: config, model: model, rules: nil)
        self.init(name: name, kind: kind, agent: agent, cwd: cwd, prompt: prompt, rules: rules,
                  byAgent: (agent.map { !over.isEmpty ? [$0: over] : [:] }).flatMap {
                      $0.isEmpty ? nil : $0
                  })
    }

    enum CodingKeys: String, CodingKey {
        case name, kind, agent, cwd, prompt, rules, byAgent
        // Onde comando, config e modelo moravam antes da ADR-057.
        case cmd, config, model
    }

    /// Componente escrito antes da ADR-057 tem `cmd`/`config`/`model` na raiz:
    /// eles eram do CLI o tempo todo, então viram o mapa daquele CLI. Sem
    /// migração de disco — o arquivo velho continua válido e é reescrito na
    /// forma nova quando você salvar o componente.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(NodeKind.self, forKey: .kind)
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        rules = try c.decodeIfPresent(String.self, forKey: .rules)
        byAgent = try c.decodeIfPresent([String: Overrides].self, forKey: .byAgent)

        let legacy = Overrides(cmd: try c.decodeIfPresent(String.self, forKey: .cmd),
                               config: try c.decodeIfPresent(String.self, forKey: .config),
                               model: try c.decodeIfPresent(String.self, forKey: .model),
                               rules: nil)
        if !legacy.isEmpty, let agent, byAgent?[agent] == nil {
            byAgent = (byAgent ?? [:]).merging([agent: legacy]) { old, _ in old }
        }
    }

    /// Grava só na forma nova: as chaves legadas existem para ler o que já está
    /// no disco, não para continuar escrevendo nelas.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(agent, forKey: .agent)
        try c.encodeIfPresent(cwd, forKey: .cwd)
        try c.encodeIfPresent(prompt, forKey: .prompt)
        try c.encodeIfPresent(rules, forKey: .rules)
        try c.encodeIfPresent(byAgent?.isEmpty == true ? nil : byAgent, forKey: .byAgent)
    }

    /// Nome legível do que este terminal roda, para o cabeçalho do nó.
    func displayAgent(using agents: [String: AgentProfile]) -> String? {
        guard kind == .agent else { return nil }
        if let agent, let profile = agents[agent] { return profile.displayName }
        return agent
    }
}

enum NodeTemplateStore {
    // O arquivo continua components.json: é editado à mão e já existe nas duas
    // casas (~/.egeon e ~/.egeon-dev). O tipo virou NodeTemplate no código; o
    // disco não precisou acompanhar, e a chave `component` do NodeConfig idem.
    static let configURL = URL(fileURLWithPath:
        Flavor.current.config("components.json").path)

    static func load() -> [String: NodeTemplate] {
        guard let data = try? Data(contentsOf: configURL),
              let map = try? JSONDecoder().decode([String: NodeTemplate].self, from: data)
        else { return [:] }
        return map
    }

    /// Ordem estável: a de um dicionário muda a cada execução, e o menu de
    /// componentes ficaria se embaralhando sozinho.
    static var names: [String] { load().keys.sorted() }

    static func save(_ map: [String: NodeTemplate]) {
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(map).write(to: configURL)
    }

    static func component(named name: String) -> NodeTemplate? { load()[name] }

    static func put(_ component: NodeTemplate) {
        var map = load()
        map[component.name] = component
        save(map)
        Log.write("componente \"\(component.name)\" salvo "
                  + "(\(component.kind.rawValue)\(component.agent.map { ", \($0)" } ?? ""))")
    }

    static func remove(named name: String) {
        var map = load()
        map[name] = nil
        save(map)
    }

    /// `front end` → `front-end`.
    ///
    /// O nome vira id, e o id entra no endereço de dispatch, que viaja em query
    /// string até a extensão do VSCode. Espaço e barra ali dão dor de cabeça.
    static func identifier(from name: String) -> String {
        let lowered = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyz0123456789-_")
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        // Colapsa repetições e apara as pontas: "front / end" não deve virar
        // "front---end".
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "sh" : collapsed
    }

    /// Converte um nó já existente em componente, para "salvar este terminal
    /// como componente".
    /// O que o nó tem de CLI entra no mapa do CLI dele; o resto é o papel. As
    /// regras do nó viram as gerais: quem captura um terminal não está dizendo
    /// que elas valem só ali (ADR-057).
    static func capture(from node: NodeConfig, name: String) -> NodeTemplate {
        let over = NodeTemplate.Overrides(cmd: node.cmd, config: node.config,
                                          model: node.model, rules: nil)
        return NodeTemplate(name: name, kind: node.type, agent: node.agent,
                            cwd: node.cwd, prompt: node.prompt, rules: node.rules,
                            byAgent: (node.agent.flatMap { key in
                                over.isEmpty ? nil : [key: over]
                            }))
    }

    /// Instancia o componente como nó, com id único dentro da bancada. O que é
    /// do CLI sai do mapa dele; o resto é o papel, e vale igual em qualquer um.
    static func instantiate(_ component: NodeTemplate, id: String) -> NodeConfig {
        let resolved = component.resolved(for: component.agent)
        var node = NodeConfig(type: component.kind, id: id)
        node.agent = component.agent
        node.cmd = resolved.cmd
        node.config = resolved.config
        node.model = resolved.model
        node.cwd = component.cwd
        node.prompt = component.prompt
        node.rules = resolved.rules
        node.component = component.name
        return node
    }
}
