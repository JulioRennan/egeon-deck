import Foundation

/// Um projeto é uma pasta — um repositório, quase sempre.
///
/// É a raiz a que as bancadas pertencem. A bancada aberta no checkout principal
/// e a aberta numa worktree dele são do MESMO projeto: saíram da mesma coisa, e
/// tratar cada worktree como projeto encheria a barra de pastas que ninguém
/// escolheu (ADR-043).
struct ProjectConfig: Codable, Equatable {
    var id: String = WorkbenchConfig.newID()
    var name: String
    var path: String
    /// Recolhido na barra lateral. Mora aqui, e não em preferência à parte,
    /// porque o arquivo é editado à mão e a árvore inteira tem de estar num
    /// lugar só.
    var collapsed: Bool?
    /// Guardado: sai da lista de cima e vai para a gaveta do workspace. É
    /// ESCOLHA sua — arrastando para lá ou pelo menu —, não dedução por tempo
    /// sem uso: projeto parado há meses pode ser o que você abre amanhã
    /// (ADR-052).
    var stored: Bool?

    var url: URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
    var isCollapsed: Bool { collapsed ?? false }
    var isStored: Bool { stored ?? false }

    /// Compara como o disco compara: `~` expandido, sem barra no fim. É o que
    /// deixa `~/Documents/deck` e `/Users/x/Documents/deck/` serem o mesmo
    /// projeto sem passar pelo `FileManager`.
    static func normalize(_ path: String) -> String {
        var p = (path as NSString).expandingTildeInPath
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    func owns(path other: String) -> Bool {
        Self.normalize(path) == Self.normalize(other)
    }

    enum CodingKeys: String, CodingKey { case id, name, path, collapsed, stored }

    /// À mão só por causa do `id`: um projeto escrito no arquivo sem ele ganha
    /// um ao carregar, como a bancada.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? WorkbenchConfig.newID()
        path = try c.decode(String.self, forKey: .path)
        name = try c.decodeIfPresent(String.self, forKey: .name)
            ?? URL(fileURLWithPath: path).lastPathComponent
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed)
        stored = try c.decodeIfPresent(Bool.self, forKey: .stored)
    }

    init(id: String = WorkbenchConfig.newID(), name: String, path: String,
         collapsed: Bool? = nil, stored: Bool? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.collapsed = collapsed
        self.stored = stored
    }

    /// Projeto novo para uma pasta: o nome é o da pasta, o caminho vai com `~`.
    static func forFolder(_ path: String) -> ProjectConfig {
        let normalized = normalize(path)
        return ProjectConfig(name: URL(fileURLWithPath: normalized).lastPathComponent,
                             path: (normalized as NSString).abbreviatingWithTildeInPath)
    }
}

/// Um workspace é um nome e um punhado de projetos. É a camada de cima da
/// organização — o que a ADR-031 recusou como nome da bancada por conotar
/// "organização inteira" é exatamente o que ele é.
///
/// Não é perfil: todos aparecem na barra ao mesmo tempo, expansíveis, porque
/// trabalhar em dois workspaces no mesmo dia é o caso normal.
struct WorkspaceConfig: Codable, Equatable {
    var id: String = WorkbenchConfig.newID()
    var name: String
    /// Nome do arquivo de imagem dentro de `workspaces/<id>/`. Ausente = a
    /// inicial numa pastilha, como a bancada já fazia no trilho.
    var icon: String?
    var projects: [ProjectConfig]
    var collapsed: Bool?
    /// A gaveta dos guardados está aberta.
    var storedOpen: Bool?

    var isCollapsed: Bool { collapsed ?? false }
    var isStoredOpen: Bool { storedOpen ?? false }
    /// Os projetos de cada lado da gaveta, na ordem em que você os deixou.
    var activeProjects: [ProjectConfig] { projects.filter { !$0.isStored } }
    var storedProjects: [ProjectConfig] { projects.filter(\.isStored) }
    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }

    func project(withID id: String) -> ProjectConfig? { projects.first { $0.id == id } }
    func project(owning path: String) -> ProjectConfig? { projects.first { $0.owns(path: path) } }

    enum CodingKeys: String, CodingKey { case id, name, icon, projects, collapsed, storedOpen }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? WorkbenchConfig.newID()
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        projects = try c.decodeIfPresent([ProjectConfig].self, forKey: .projects) ?? []
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed)
        storedOpen = try c.decodeIfPresent(Bool.self, forKey: .storedOpen)
    }

    init(id: String = WorkbenchConfig.newID(), name: String, icon: String? = nil,
         projects: [ProjectConfig] = [], collapsed: Bool? = nil, storedOpen: Bool? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.projects = projects
        self.collapsed = collapsed
        self.storedOpen = storedOpen
    }
}
