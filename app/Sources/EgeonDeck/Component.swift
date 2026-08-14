import Foundation

/// Preset de um terminal: o papel que ele cumpre.
///
/// Três camadas, e esta é a do meio:
/// - `agents.json` diz COMO falar com um CLI (bracketed paste, silêncio, resume)
/// - o componente diz O QUE este terminal é (revisor, front, shell de build)
/// - `templates.json` diz o ARRANJO dos nós no canvas
///
/// O componente referencia um perfil de agente; não o substitui.
struct Component: Codable {
    /// Nome que virou o id do nó, e por isso aparece no endereço de dispatch:
    /// `deck/revisor`.
    var name: String
    /// `shell` ou `agent`. Editar um nó pode trocar de um para o outro.
    var kind: NodeKind
    /// Chave em agents.json. Só para `agent`.
    var agent: String?
    /// Comando completo, quando o padrão do perfil não serve — outro binário,
    /// outra flag. Para escolher entre configurações do MESMO CLI existe o
    /// `config`, que não mexe na linha de comando.
    var cmd: String?
    /// Pasta de configuração do CLI: com qual conjunto de plugins, MCP, settings
    /// e credenciais este terminal sobe. Absoluto, e só para `agent`.
    ///
    /// Vai para a variável que o perfil declara em `configEnv` — o nome é da CLI,
    /// não nosso. Nulo é o padrão dela.
    ///
    /// Absoluto ao contrário do `cwd`, e é a diferença que importa: `cwd` é
    /// dentro da sessão, e o mesmo componente tem de valer em qualquer worktree;
    /// a configuração é da máquina, e a mesma pasta vale para todas as sessões.
    var config: String?
    /// Relativo à raiz da sessão — nunca absoluto. É o que faz o mesmo
    /// componente valer em qualquer worktree.
    var cwd: String?
    /// Mensagem entregue ao agente quando ele sobe. Vai pela fila do Dispatcher,
    /// que espera o `warmupMs` do perfil e o silêncio do pty: injetar antes de a
    /// TUI ter leitor de stdin perde o texto.
    var prompt: String?

    /// Nome legível do que este terminal roda, para o cabeçalho do nó.
    func displayAgent(using agents: [String: AgentProfile]) -> String? {
        guard kind == .agent else { return nil }
        if let agent, let profile = agents[agent] { return profile.displayName }
        return agent
    }
}

enum ComponentStore {
    static let configURL = URL(fileURLWithPath:
        Flavor.current.config("components.json").path)

    static func load() -> [String: Component] {
        guard let data = try? Data(contentsOf: configURL),
              let map = try? JSONDecoder().decode([String: Component].self, from: data)
        else { return [:] }
        return map
    }

    /// Ordem estável: a de um dicionário muda a cada execução, e o menu de
    /// componentes ficaria se embaralhando sozinho.
    static var names: [String] { load().keys.sorted() }

    static func save(_ map: [String: Component]) {
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(map).write(to: configURL)
    }

    static func component(named name: String) -> Component? { load()[name] }

    static func put(_ component: Component) {
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
    static func capture(from node: NodeConfig, name: String) -> Component {
        Component(name: name,
                  kind: node.type,
                  agent: node.agent,
                  cmd: node.cmd,
                  config: node.config,
                  cwd: node.cwd,
                  prompt: node.prompt)
    }

    /// Instancia o componente como nó, com id único dentro da sessão.
    static func instantiate(_ component: Component, id: String) -> NodeConfig {
        var node = NodeConfig(type: component.kind, id: id)
        node.agent = component.agent
        node.cmd = component.cmd
        node.config = component.config
        node.cwd = component.cwd
        node.prompt = component.prompt
        node.component = component.name
        return node
    }
}
