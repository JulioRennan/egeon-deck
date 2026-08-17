import CoreGraphics
import Foundation

enum NodeKind: String, Codable {
    case editor   // code-server no WKWebView
    case shell    // terminal comum
    case agent    // terminal com IA
    case web      // navegador no canvas, com perfil próprio
}

struct NodeConfig: Codable {
    let type: NodeKind
    let id: String
    /// Chave em agents.json. Só usado por `type: agent`.
    var agent: String?
    /// Relativo à raiz da sessão.
    var cwd: String?
    /// Comando inicial. Em `agent`, o padrão vem do perfil.
    var cmd: String?
    /// Pasta de configuração do CLI — com qual conjunto de plugins, MCP e
    /// settings este terminal sobe. Absoluto, e entregue pela variável que o
    /// perfil declara em `configEnv`. Nulo é o padrão da CLI.
    var config: String?
    /// Só usado por `type: web`.
    var url: String?
    /// Nome do perfil em web-profiles.json. Só usado por `type: web`.
    var profile: String?

    /// Mensagem entregue ao agente quando ele sobe — o papel deste terminal.
    /// Entra na fila do Dispatcher, que espera a TUI aceitar stdin.
    var prompt: String?
    /// Componente que originou o nó. Só registro: os valores foram copiados, e
    /// editar o componente depois não mexe em quem já nasceu.
    var component: String?

    /// Conversa deste terminal no CLI do agente. Gerado na primeira subida e
    /// guardado daí em diante — é o que permite retomar depois de um rebuild.
    ///
    /// Vive no NÓ e não é derivado da pasta de propósito: dois agentes na mesma
    /// worktree têm conversas separadas, e o `--continue` do Claude Code, que pega
    /// a mais recente do diretório, entregaria a mesma para os dois.
    var sessionId: String?

    /// O terminal já subiu uma vez com este `sessionId`?
    ///
    /// Separado do id porque a estreia usa flag diferente da retomada. Sem isso a
    /// primeira subida tentaria retomar uma conversa que não existe e mostraria
    /// "No conversation found" antes de criar — funciona, mas suja a tela toda vez
    /// que você cria um terminal.
    var sessionStarted: Bool?

    /// Ausente significa "nunca subiu": nó gravado antes deste campo existir não
    /// o tem.
    var hasStartedSession: Bool { sessionStarted ?? false }

    /// O mesmo nó, sem a conversa — pronto para nascer em outro lugar.
    ///
    /// Copiar um nó é copiar a montagem, nunca o que foi dito dentro dele. Com o
    /// `sessionId` junto, o clone e o original apontam para a MESMA conversa e o
    /// segundo a subir não consegue abri-la: o terminal mostra a TUI desenhada e
    /// morre em seguida, sem erro visível no app. Vale para o template e para a
    /// duplicação em worktree.
    var withoutConversation: NodeConfig {
        var copy = self
        copy.sessionId = nil
        copy.sessionStarted = nil
        return copy
    }

    /// Posição e tamanho no canvas. Ausente na primeira vez: o app calcula o
    /// layout automático e grava o resultado, então a partir daí o que manda é
    /// onde o nó está de fato.
    var x: Double?
    var y: Double?
    var w: Double?
    var h: Double?

    var frame: CGRect? {
        guard let x, let y, let w, let h, w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    mutating func setFrame(_ rect: CGRect) {
        x = Double(rect.minX.rounded())
        y = Double(rect.minY.rounded())
        w = Double(rect.width.rounded())
        h = Double(rect.height.rounded())
    }
}

/// Uma frente de trabalho: uma pasta e os nós abertos sobre ela.
///
/// Sessão, e não projeto: nada impede duas sessões apontarem para o mesmo
/// repositório em worktrees diferentes, ou para a mesma pasta com nós
/// diferentes. Elas são independentes de propósito.
struct SessionConfig: Codable {
    /// Renomeável. É também a primeira parte do endereço de dispatch, então
    /// trocar o nome exige re-registrar os alvos vivos — ver `Dispatcher.rekey`.
    var name: String
    var path: String
    var nodes: [NodeConfig]
    /// Template que originou a sessão. Só registro — a sessão não fica atada a
    /// ele, e editar o template depois não mexe em quem já nasceu.
    var template: String?

    /// Quem pode acionar quem, dentro desta sessão.
    var edges: [EdgeConfig]?

    /// Teto de revisitas de um mesmo terminal numa cadeia. É rede de segurança,
    /// não o botão do dia a dia — quem você regula é o limite da aresta.
    ///
    /// Existe porque limite por aresta não segura `A→B→C→A`: ali cada seta
    /// dispara uma vez só e o limite dela nunca chega perto. Só o contador da
    /// cadeia inteira fecha essa porta.
    ///
    /// Conta revisita, e não comprimento: `pm → front → pm → back → pm` é
    /// orquestração normal, e cortar por comprimento estrangularia trabalho
    /// legítimo. O que precisa de teto é a volta.
    var maxVisits: Int?

    /// De que jeito esta sessão estava sendo olhada. Ausente = canvas.
    ///
    /// Por sessão e não global: uma frente com um editor e quatro agentes pede
    /// mosaico, e a do lado, com dois terminais soltos e as arestas à vista, pede
    /// canvas.
    var view: ViewMode?

    /// Proporções dos divisores do mosaico, quando você já arrastou algum.
    var mosaic: MosaicLayout?

    var viewMode: ViewMode { view ?? .canvas }

    var edgeList: [EdgeConfig] { edges ?? [] }
    /// Folgado o bastante para uma orquestração de três nós passar sem esbarrar
    /// nele — o corte que você sente no dia a dia deve vir da aresta.
    var visitLimit: Int { maxVisits ?? 4 }

    /// Para onde `node` pode mandar mensagem.
    func targets(of node: String) -> [String] {
        edgeList.filter { $0.from == node }.map(\.to)
    }

    var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
    var folderName: String { url.lastPathComponent }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Endereço de dispatch: estável, independe de título de janela ou posição
    /// na tela.
    func address(of node: NodeConfig) -> String { "\(name)/\(node.id)" }

    /// Para onde um `cwd` de nó aponta, sem perguntar ao disco.
    ///
    /// Três formas são legítimas e cada uma tem seu motivo:
    ///
    /// - **relativo** (`packages/api`) é o caso normal, e é o que faz o nó valer em
    ///   qualquer checkout — é dele que a duplicação em worktree depende
    /// - **absoluto** (`~/Documents/agrosmart/nexus-backend`) é um repositório
    ///   vizinho, que não tem equivalente dentro da worktree da sessão
    /// - **relativo saindo da raiz** (`../nexus-backend`) também aponta para fora, e
    ///   é onde mora a armadilha: o mesmo texto significa pastas diferentes em
    ///   checkouts diferentes
    ///
    /// `standardized` resolve o `..` de forma lexical, o que é o que se quer aqui:
    /// o caminho tem de ser previsível a partir do texto, sem depender de symlink.
    static func resolve(cwd: String, against root: URL) -> String {
        if cwd.hasPrefix("~") || cwd.hasPrefix("/") {
            return (cwd as NSString).expandingTildeInPath
        }
        return root.appendingPathComponent(cwd).standardized.path
    }

    func resolvedDirectory(for node: NodeConfig) -> String {
        guard let cwd = node.cwd else { return url.path }
        return Self.resolve(cwd: cwd, against: url)
    }

    /// Onde o processo deste nó é lançado.
    ///
    /// `cwd` que não resolve cai na raiz da sessão — mas **falando**. Calado, este
    /// fallback é o pior defeito que este arquivo já teve: o terminal abre na pasta
    /// errada, fica com a cara do terminal certo, e o agente trabalha no
    /// repositório vizinho sem ninguém suspeitar. Custou um dia de trabalho, com
    /// `../nexus-backend` carregado literal para dentro de uma worktree onde `..`
    /// é outro lugar.
    func directory(for node: NodeConfig) -> String {
        guard node.cwd != nil else { return url.path }
        let candidate = resolvedDirectory(for: node)
        guard !FileManager.default.fileExists(atPath: candidate) else { return candidate }

        Log.write("sessão \(name): nó \"\(node.id)\" pede cwd \"\(node.cwd ?? "")\", que resolve "
                  + "em \(candidate) e não existe — vai abrir na raiz \(url.path)",
                  key: "cwd.\(name).\(node.id)")
        return url.path
    }

    /// Nós cujo `cwd` não resolve, com o caminho que cada um tentou.
    ///
    /// Serve para dizer na cara, na hora de montar a sessão, em vez de deixar o
    /// usuário descobrir pelo `pwd` três horas depois.
    var unresolvedDirectories: [(id: String, tried: String)] {
        nodes.compactMap { node in
            guard node.cwd != nil else { return nil }
            let candidate = resolvedDirectory(for: node)
            guard !FileManager.default.fileExists(atPath: candidate) else { return nil }
            return (node.id, candidate)
        }
    }
}

/// Ganchos que a UI publica para o socket de controle. Evita o socket segurar
/// referência ao AppDelegate e permite dirigir o app de fora — o que também é
/// o que a extensão do VSCode precisa para trocar de sessão.
enum AppControl {
    static var activateSession: ((String) -> Bool)?
    static var sessionNames: (() -> [String])?

    /// PNG do card de um nó — cabeçalho, borda e corpo, como está na tela.
    ///
    /// Mudança que é só desenho não tem log nem DOM para conferir: ou se olha a
    /// imagem, ou se acredita. Devolve o caminho do arquivo, ou o erro.
    static var cardSnapshot: ((_ target: String, _ file: URL) -> String)?

    /// Remove uma sessão, opcionalmente apagando as worktrees dela.
    ///
    /// Existe pelo mesmo motivo que `makeWorktree`: o fluxo passa por `NSAlert`, que
    /// não é dirigível de fora, e "apaguei todas as worktrees" é exatamente o tipo
    /// de afirmação que precisa ser conferida em repositório de verdade.
    static var removeSession: ((_ name: String, _ purge: Bool) -> [String: Any])?

    /// Qual sessão é dona de uma pasta.
    ///
    /// A extensão do editor sabe a pasta do workspace e mais nada — quem conhece
    /// a topologia é o app. Sem isto, a única lista que ela conseguia pedir era a
    /// global, e o editor de um projeto sugeria terminal de outro.
    static var sessionOwning: ((String) -> String?)?
    /// Geometria dos nós do canvas ativo, já em coordenadas de tela com origem
    /// no topo — as mesmas do CGEvent. Serve para dirigir e verificar gestos de
    /// fora sem depender de estimar pixel em captura de tela.
    static var canvasGeometry: (() -> [String: Any])?

    /// Troca a visualização da sessão ativa — canvas ou mosaico.
    ///
    /// Existe pelo mesmo motivo que `/geometry`: dirigir e verificar o app de fora
    /// sem depender de gesto na tela. Nulo de volta significa modo desconhecido ou
    /// nenhuma sessão ativa.
    static var setViewMode: ((String) -> String?)?

    /// Cria worktree e reaponta: `sessão` duplica a sessão inteira levando os
    /// terminais de repo vizinho junto, `sessão/nó` leva só aquele terminal.
    ///
    /// Existe pelo mesmo motivo que `/geometry` e `/layout`: o fluxo passa por
    /// `NSAlert`, que não é dirigível de fora, e sem isto não haveria como
    /// verificar que cada terminal foi para a pasta certa — que é justamente o
    /// defeito que este código conserta. Devolve o que aconteceu, ou o erro.
    static var makeWorktree: ((_ target: String, _ branch: String,
                              _ nodeBranches: [String: String]) -> [String: Any])?

    /// Ligações e teto de revisitas de uma sessão, por nome.
    ///
    /// O Dispatcher precisa dos dois para validar mensagem entre agentes, e não
    /// conhece o `sessions.json` — quem conhece é o AppDelegate. Mesmo arranjo
    /// dos ganchos acima, e pelo mesmo motivo: evita o Dispatcher segurar
    /// referência à UI.
    static var sessionEdges: ((String) -> [EdgeConfig])?
    static var sessionVisitLimit: ((String) -> Int)?
    /// Papel do nó, para a lista de vizinhos dizer o que cada um faz — sem isso
    /// o agente lê endereços e não tem como escolher entre dois irmãos.
    static var nodeRole: ((String) -> String?)?

    /// O CLI avisou qual conversa está aberta neste terminal. Chamado a cada
    /// prompt, então quem implementa só grava quando o valor muda de fato.
    static var recordSession: ((_ target: String, _ id: String) -> Void)?
}

enum SessionStore {
    static let configURL = URL(fileURLWithPath:
        Flavor.current.config("sessions.json").path)

    static func load() -> [SessionConfig] {
        if let list = decode(configURL) { return list }

        // Sem nada para carregar, começa vazio: chutar caminhos de projeto só
        // produz sessões quebradas que o usuário tem de limpar.
        return []
    }

    private static func decode(_ url: URL) -> [SessionConfig]? {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([SessionConfig].self, from: data),
              !list.isEmpty else { return nil }
        return list
    }

    static func save(_ list: [SessionConfig]) {
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(list).write(to: configURL)
    }

    /// Nome livre derivado da pasta: `deck`, `deck-2`, `deck-3`…
    /// O nome é a primeira parte do endereço de dispatch, então precisa ser único.
    static func availableName(basedOn suggestion: String, taken: [String]) -> String {
        let base = suggestion.isEmpty ? "sessao" : suggestion
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}
