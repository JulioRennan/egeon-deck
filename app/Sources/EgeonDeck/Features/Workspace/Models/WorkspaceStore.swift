import Foundation

enum WorkspaceStore {
    static let configURL = URL(fileURLWithPath:
        Flavor.current.config("workspaces.json").path)

    /// Nome do workspace que nasce sozinho na primeira carga. Quem já tinha
    /// bancadas não escolheu workspace nenhum, e elas precisam de um teto.
    static let defaultName = "Geral"

    /// `nil` quando o arquivo não existe — é o que dispara a migração. Arquivo
    /// vazio é uma lista vazia, e a migração também recria o padrão.
    static func load() -> [WorkspaceConfig]? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return (try? JSONDecoder().decode([WorkspaceConfig].self, from: data)) ?? []
    }

    static func save(_ list: [WorkspaceConfig]) {
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(list).write(to: configURL)
    }

    // MARK: - Imagem

    static func iconURL(of workspace: WorkspaceConfig) -> URL? {
        guard let icon = workspace.icon else { return nil }
        return Flavor.current.workspaceDirectory(workspace.id).appendingPathComponent(icon)
    }

    /// Copia a imagem escolhida para a pasta do workspace e aponta `icon` para
    /// ela. Cópia, e não referência: a original pode estar em Downloads e sumir
    /// na semana seguinte.
    static func installIcon(from source: URL, into workspace: inout WorkspaceConfig) throws {
        let dir = Flavor.current.workspaceDirectory(workspace.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let name = "icon.\(ext)"
        let destination = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        if let old = workspace.icon, old != name {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(old))
        }
        workspace.icon = name
    }

    static func removeIcon(of workspace: inout WorkspaceConfig) {
        if let url = iconURL(of: workspace) { try? FileManager.default.removeItem(at: url) }
        workspace.icon = nil
    }

    // MARK: - Conciliação

    struct Reconciled {
        var workspaces: [WorkspaceConfig]
        var workbenches: [WorkbenchConfig]
        /// Alguma coisa mudou e precisa ir para o disco.
        var changed: Bool
        /// O que foi decidido sem você, para o log.
        var notes: [String]
    }

    /// Dá projeto a toda bancada que não tem um, criando o que faltar.
    ///
    /// Roda na carga e depois de toda bancada criada por caminho livre. A regra
    /// de pertencimento é uma só: a bancada é do projeto cuja pasta é o
    /// repositório principal dela — `mainRepo` resolve worktree para o checkout
    /// de origem, e é injetado porque é git, e o teste não quer git.
    ///
    /// Bancada com `project` apontando para id que não existe mais é tratada
    /// como sem projeto: o arquivo é editável à mão e o id pode ter sido apagado.
    static func reconcile(workspaces: [WorkspaceConfig], workbenches: [WorkbenchConfig],
                          mainRepo: (String) -> String?) -> Reconciled {
        var spaces = workspaces
        var benches = workbenches
        var changed = false
        var notes: [String] = []

        if spaces.isEmpty {
            spaces = [WorkspaceConfig(name: defaultName)]
            changed = true
            notes.append("workspace \"\(defaultName)\" criado")
        }

        func locate(projectID: String) -> Bool {
            spaces.contains { $0.project(withID: projectID) != nil }
        }
        func locate(path: String) -> String? {
            for space in spaces {
                if let project = space.project(owning: path) { return project.id }
            }
            return nil
        }

        for i in benches.indices {
            if let id = benches[i].project, locate(projectID: id) { continue }

            let path = benches[i].url.path
            let root = mainRepo(path) ?? path
            if let id = locate(path: root) {
                benches[i].project = id
                changed = true
                continue
            }

            let project = ProjectConfig.forFolder(root)
            spaces[0].projects.append(project)
            benches[i].project = project.id
            changed = true
            notes.append("projeto \"\(project.name)\" criado em \"\(spaces[0].name)\" "
                         + "para a bancada \"\(benches[i].name)\"")
        }

        return Reconciled(workspaces: spaces, workbenches: benches, changed: changed, notes: notes)
    }
}
