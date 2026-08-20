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
    /// Relativo à raiz da bancada.
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
    var conversationId: String?

    /// Onde o CLI está gravando esta conversa.
    ///
    /// Relatado pelo gancho, que recebe `transcript_path` no payload, e guardado
    /// aqui porque o modo Chat precisa dele no arranque — antes do primeiro prompt
    /// não haveria gancho nenhum e o thread nasceria vazio numa conversa cheia.
    ///
    /// Não é derivado do id da conversa mais convenção de pasta: isso amarraria o app
    /// ao `CLAUDE_CONFIG_DIR` do usuário, que é config de CLI e não é assunto
    /// nosso. Quem sabe onde grava é quem grava.
    var transcript: String?

    /// O terminal já subiu uma vez com esta conversa?
    ///
    /// Separado do id porque a estreia usa flag diferente da retomada. Sem isso a
    /// primeira subida tentaria retomar uma conversa que não existe e mostraria
    /// "No conversation found" antes de criar — funciona, mas suja a tela toda vez
    /// que você cria um terminal.
    var conversationStarted: Bool?

    /// Ausente significa "nunca subiu": nó gravado antes deste campo existir não
    /// o tem.
    var hasStartedConversation: Bool { conversationStarted ?? false }

    /// Os nomes antigos dos dois campos acima. **Não use**: eles existem só para ler
    /// arquivo gravado por versão anterior, são absorvidos na carga por
    /// `migratingLegacyNames` e nunca voltam ao disco — o encoder sintetizado omite
    /// opcional nulo.
    ///
    /// O campo se chamava `sessionId` porque o CLI chama a conversa de sessão. Aqui
    /// dentro isso colidia com a bancada do app e com o `Target` do Dispatcher: três
    /// coisas diferentes, uma palavra.
    ///
    /// Internos e não `private` porque propriedade privada torna PRIVADO o init
    /// membro-a-membro sintetizado, e é por ele que todo nó nasce.
    var sessionId: String?
    var sessionStarted: Bool?

    /// O nó com os nomes antigos absorvidos.
    var migratingLegacyNames: NodeConfig {
        var copy = self
        if copy.conversationId == nil { copy.conversationId = copy.sessionId }
        if copy.conversationStarted == nil { copy.conversationStarted = copy.sessionStarted }
        copy.sessionId = nil
        copy.sessionStarted = nil
        return copy
    }

    /// O mesmo nó, sem a conversa — pronto para nascer em outro lugar.
    ///
    /// Copiar um nó é copiar a montagem, nunca o que foi dito dentro dele. Com o
    /// `conversationId` junto, o clone e o original apontam para a MESMA conversa e o
    /// segundo a subir não consegue abri-la: o terminal mostra a TUI desenhada e
    /// morre em seguida, sem erro visível no app. Vale para o template e para a
    /// duplicação em worktree.
    var withoutConversation: NodeConfig {
        var copy = self
        copy.conversationId = nil
        copy.conversationStarted = nil
        // O transcript é da conversa, não da montagem: mantê-lo faria o chat do
        // clone mostrar o thread do original.
        copy.transcript = nil
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
/// Bancada, e não projeto: nada impede duas bancadas apontarem para o mesmo
/// repositório em worktrees diferentes, ou para a mesma pasta com nós
/// diferentes. Elas são independentes de propósito.
struct WorkbenchConfig: Codable {
    /// Renomeável. É também a primeira parte do endereço de dispatch, então
    /// trocar o nome exige re-registrar os alvos vivos — ver `Dispatcher.rekey`.
    var name: String
    var path: String
    var nodes: [NodeConfig]
    /// Template que originou a bancada. Só registro — a bancada não fica atada a
    /// ele, e editar o template depois não mexe em quem já nasceu.
    var template: String?

    /// Quem pode acionar quem, dentro desta bancada.
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

    /// De que jeito esta bancada estava sendo olhada. Ausente = canvas.
    ///
    /// Por bancada e não global: uma frente com um editor e quatro agentes pede
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
    ///   vizinho, que não tem equivalente dentro da worktree da bancada
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
    /// `cwd` que não resolve cai na raiz da bancada — mas **falando**. Calado, este
    /// fallback é o pior defeito que este arquivo já teve: o terminal abre na pasta
    /// errada, fica com a cara do terminal certo, e o agente trabalha no
    /// repositório vizinho sem ninguém suspeitar. Custou um dia de trabalho, com
    /// `../nexus-backend` carregado literal para dentro de uma worktree onde `..`
    /// é outro lugar.
    func directory(for node: NodeConfig) -> String {
        guard node.cwd != nil else { return url.path }
        let candidate = resolvedDirectory(for: node)
        guard !FileManager.default.fileExists(atPath: candidate) else { return candidate }

        Log.write("bancada \(name): nó \"\(node.id)\" pede cwd \"\(node.cwd ?? "")\", que resolve "
                  + "em \(candidate) e não existe — vai abrir na raiz \(url.path)",
                  key: "cwd.\(name).\(node.id)")
        return url.path
    }

    /// Nós cujo `cwd` não resolve, com o caminho que cada um tentou.
    ///
    /// Serve para dizer na cara, na hora de montar a bancada, em vez de deixar o
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
/// o que a extensão do VSCode precisa para trocar de bancada.
enum AppControl {
    static var activateWorkbench: ((String) -> Bool)?
    static var workbenchNames: (() -> [String])?

    /// Troca dois cards de painel no mosaico da bancada ativa.
    ///
    /// O gesto de arrastar o cabeçalho não é dirigível de fora — evento de mouse
    /// sintético exige permissão de Acessibilidade, que a assinatura ad-hoc perde a
    /// cada build (ADR-003). O que precisa ser verificado é o arranjo: quem foi para
    /// qual painel, e se aquilo sobreviveu ao `workbenches.json`.
    static var swapMosaic: ((_ workbench: String, _ first: String, _ second: String)
                            -> [String: Any])?

    /// Direção de uma ligação: criar, apontar para um lado, ou ciclar.
    ///
    /// Existe pelo mesmo motivo do `swapMosaic`: desenhar aresta é arrasto e trocar
    /// direção é clique num botão de 24pt, e nenhum dos dois é dirigível de fora —
    /// evento sintético exige Acessibilidade, que a assinatura ad-hoc perde a cada
    /// build (ADR-003). Sem esta rota não há como verificar que o par nasce nos dois
    /// sentidos nem que o ciclo do botão passa onde deve.
    static var setEdgeDirection: ((_ workbench: String, _ from: String, _ to: String,
                                   _ direction: String) -> [String: Any])?

    /// PNG do card de um nó — cabeçalho, borda e corpo, como está na tela.
    ///
    /// Mudança que é só desenho não tem log nem DOM para conferir: ou se olha a
    /// imagem, ou se acredita. Devolve o caminho do arquivo, ou o erro.
    static var cardSnapshot: ((_ target: String, _ file: URL) -> String)?

    /// Remove uma bancada, opcionalmente apagando as worktrees dela.
    ///
    /// Existe pelo mesmo motivo que `makeWorktree`: o fluxo passa por `NSAlert`, que
    /// não é dirigível de fora, e "apaguei todas as worktrees" é exatamente o tipo
    /// de afirmação que precisa ser conferida em repositório de verdade.
    static var removeWorkbench: ((_ name: String, _ purge: Bool) -> [String: Any])?

    /// Qual bancada é dona de uma pasta.
    ///
    /// A extensão do editor sabe a pasta do workspace e mais nada — quem conhece
    /// a topologia é o app. Sem isto, a única lista que ela conseguia pedir era a
    /// global, e o editor de um projeto sugeria terminal de outro.
    static var workbenchOwning: ((String) -> String?)?
    /// Geometria dos nós do canvas ativo, já em coordenadas de tela com origem
    /// no topo — as mesmas do CGEvent. Serve para dirigir e verificar gestos de
    /// fora sem depender de estimar pixel em captura de tela.
    static var canvasGeometry: (() -> [String: Any])?

    /// Troca a visualização da bancada ativa — canvas ou mosaico.
    ///
    /// Existe pelo mesmo motivo que `/geometry`: dirigir e verificar o app de fora
    /// sem depender de gesto na tela. Nulo de volta significa modo desconhecido ou
    /// nenhuma bancada ativa.
    static var setViewMode: ((String) -> String?)?

    /// Recolher a barra de bancadas ao trilho, ou abrir.
    ///
    /// Existe pelo mesmo motivo que `/mosaic?swap=`: recolher é tecla de menu e
    /// clique, e nenhum dos dois é dirigível de fora sem permissão de
    /// Acessibilidade, que a assinatura ad-hoc perde a cada build (ADR-003). Sem
    /// esta rota não há como conferir de fora o que a barra faz por cima de um
    /// card. Devolve se ficou recolhida.
    static var collapseSidebar: ((Bool) -> Bool)?

    /// O mesmo que o ⌘/ e o botão da barra fazem. Devolve se ficou recolhida.
    static var toggleSidebar: (() -> Bool)?

    /// Cria worktree e reaponta: `bancada` duplica a bancada inteira levando os
    /// terminais de repo vizinho junto, `bancada/nó` leva só aquele terminal.
    ///
    /// Existe pelo mesmo motivo que `/geometry` e `/layout`: o fluxo passa por
    /// `NSAlert`, que não é dirigível de fora, e sem isto não haveria como
    /// verificar que cada terminal foi para a pasta certa — que é justamente o
    /// defeito que este código conserta. Devolve o que aconteceu, ou o erro.
    static var makeWorktree: ((_ target: String, _ branch: String,
                              _ nodeBranches: [String: String]) -> [String: Any])?

    /// Ligações e teto de revisitas de uma bancada, por nome.
    ///
    /// O Dispatcher precisa dos dois para validar mensagem entre agentes, e não
    /// conhece o `workbenches.json` — quem conhece é o AppDelegate. Mesmo arranjo
    /// dos ganchos acima, e pelo mesmo motivo: evita o Dispatcher segurar
    /// referência à UI.
    static var workbenchEdges: ((String) -> [EdgeConfig])?
    static var workbenchVisitLimit: ((String) -> Int)?
    /// Papel do nó, para a lista de vizinhos dizer o que cada um faz — sem isso
    /// o agente lê endereços e não tem como escolher entre dois irmãos.
    static var nodeRole: ((String) -> String?)?

    /// O CLI avisou qual conversa está aberta neste terminal. Chamado a cada
    /// prompt, então quem implementa só grava quando o valor muda de fato.
    static var recordConversation: ((_ target: String, _ id: String, _ transcript: String?) -> Void)?

    /// O thread do modo Chat de uma bancada, como dados.
    ///
    /// Existe pelo mesmo motivo do `/peek`: o thread é montado de vários arquivos,
    /// e "a mensagem do dev-backend apareceu depois da sua, com o diff certo" é
    /// exatamente o tipo de afirmação que não se confere olhando print. Aqui dá
    /// para ver a ordem, o autor e os blocos de cada mensagem sem abrir o app.
    static var chatThread: ((String) -> [String: Any]?)?

    /// Escreve na caixa do modo Chat, sem enviar, e devolve a geometria.
    ///
    /// Existe pelo mesmo motivo do `swapMosaic` e do `setEdgeDirection`: crescer a
    /// caixa é digitar, e tecla sintética exige Acessibilidade, que a assinatura
    /// ad-hoc perde a cada build (ADR-003). Sem esta rota, "a caixa cresce para cima e
    /// o histórico cede a área" é afirmação sem evidência.
    static var chatCompose: ((_ workbench: String, _ text: String, _ send: Bool)
                             -> [String: Any]?)?
}

enum WorkbenchStore {
    static let configURL = URL(fileURLWithPath:
        Flavor.current.config("workbenches.json").path)

    /// Onde o arquivo morava quando bancada se chamava sessão. Lido só quando o novo
    /// não existe, e nunca escrito: a primeira gravação já sai com o nome novo.
    private static let legacyURL = URL(fileURLWithPath:
        Flavor.current.config("sessions.json").path)

    static func load() -> [WorkbenchConfig] {
        if let list = decode(configURL) { return list }
        if let list = decode(legacyURL) {
            Log.write("bancadas: lidas do sessions.json antigo; "
                      + "a próxima gravação vai para \(configURL.lastPathComponent)")
            return list
        }

        // Sem nada para carregar, começa vazio: chutar caminhos de projeto só
        // produz bancadas quebradas que o usuário tem de limpar.
        return []
    }

    private static func decode(_ url: URL) -> [WorkbenchConfig]? {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([WorkbenchConfig].self, from: data),
              !list.isEmpty else { return nil }
        // Arquivo gravado antes do rename traz `sessionId`/`sessionStarted`. Sem
        // absorver aqui, todo agente perderia a conversa no primeiro arranque desta
        // versão — o terminal subiria limpo e o thread do chat nasceria vazio.
        return list.map { config in
            var copy = config
            copy.nodes = config.nodes.map(\.migratingLegacyNames)
            return copy
        }
    }

    static func save(_ list: [WorkbenchConfig]) {
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(list).write(to: configURL)
    }

    /// Nome livre derivado da pasta: `deck`, `deck-2`, `deck-3`…
    /// O nome é a primeira parte do endereço de dispatch, então precisa ser único.
    static func availableName(basedOn suggestion: String, taken: [String]) -> String {
        let base = suggestion.isEmpty ? "bancada" : suggestion
        guard taken.contains(base) else { return base }
        var n = 2
        while taken.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }
}
