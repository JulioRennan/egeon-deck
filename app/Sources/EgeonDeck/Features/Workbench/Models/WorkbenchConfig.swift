import CoreGraphics
import Foundation

/// Uma frente de trabalho: uma pasta e os nós abertos sobre ela.
///
/// Bancada, e não projeto: nada impede duas bancadas apontarem para o mesmo
/// repositório em worktrees diferentes, ou para a mesma pasta com nós
/// diferentes. Elas são independentes de propósito.
struct WorkbenchConfig: Codable {
    /// Identidade que o nome não dá: apagar uma bancada e criar outra com o
    /// mesmo nome é outra bancada, e o que é dela em disco (a trilha) não pode
    /// se misturar. Nasce com a bancada e nunca muda; bancada gravada antes de
    /// existir ganha um ao carregar. Oito hex de um UUID: único o bastante para
    /// uma máquina, curto o bastante para ser nome de pasta.
    var id: String = WorkbenchConfig.newID()
    /// Renomeável. É também a primeira parte do endereço de dispatch, então
    /// trocar o nome exige re-registrar os alvos vivos — ver `Dispatcher.rekey`.
    var name: String
    var path: String
    var nodes: [NodeConfig]
    /// Template que originou a bancada. Só registro — a bancada não fica atada a
    /// ele, e editar o template depois não mexe em quem já nasceu.
    var template: String?

    /// Projeto (id) a que a bancada pertence, na árvore workspace → projeto →
    /// bancada (ADR-043). Ausente = ainda não conciliado; `WorkspaceStore.reconcile`
    /// resolve pelo repositório principal da pasta.
    var project: String?

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

    /// As regras desta bancada: valem para TODO agente que abre aqui, e cada nó
    /// pode somar as suas.
    ///
    /// É o que faz o campo existir em vez de estar dentro do papel: "não commite
    /// sem me perguntar" é da frente de trabalho, não de um terminal — escrito
    /// uma vez, vale para os quatro (ADR-056).
    var rules: String?

    /// De que jeito esta bancada estava sendo olhada. Ausente = canvas.
    ///
    /// Por bancada e não global: uma frente com um editor e quatro agentes pede
    /// mosaico, e a do lado, com dois terminais soltos e as arestas à vista, pede
    /// canvas.
    var view: ViewMode?

    /// Proporções dos divisores do mosaico, quando você já arrastou algum.
    var mosaic: MosaicLayout?

    var viewMode: ViewMode { view ?? .canvas }

    static func newID() -> String {
        String(UUID().uuidString.lowercased().prefix(8))
    }

    enum CodingKeys: String, CodingKey {
        case id, name, path, nodes, template, project, edges, maxVisits, rules, view, mosaic
    }

    /// Escrito à mão só por causa do `id`: o decoder sintetizado exige a chave
    /// de campo não opcional, e o `workbenches.json` de antes não a tem.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? WorkbenchConfig.newID()
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        nodes = try c.decodeIfPresent([NodeConfig].self, forKey: .nodes) ?? []
        template = try c.decodeIfPresent(String.self, forKey: .template)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        edges = try c.decodeIfPresent([EdgeConfig].self, forKey: .edges)
        maxVisits = try c.decodeIfPresent(Int.self, forKey: .maxVisits)
        rules = try c.decodeIfPresent(String.self, forKey: .rules)
        view = try c.decodeIfPresent(ViewMode.self, forKey: .view)
        mosaic = try c.decodeIfPresent(MosaicLayout.self, forKey: .mosaic)
    }

    init(id: String = WorkbenchConfig.newID(), name: String, path: String, nodes: [NodeConfig],
         template: String? = nil, project: String? = nil, edges: [EdgeConfig]? = nil,
         maxVisits: Int? = nil, rules: String? = nil,
         view: ViewMode? = nil, mosaic: MosaicLayout? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.nodes = nodes
        self.template = template
        self.project = project
        self.edges = edges
        self.maxVisits = maxVisits
        self.rules = rules
        self.view = view
        self.mosaic = mosaic
    }

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
