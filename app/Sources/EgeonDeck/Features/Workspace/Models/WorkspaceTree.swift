import Foundation

/// O que a barra lateral lista, na ordem, já respeitando o que está recolhido.
enum SidebarItem: Equatable {
    case workspace(id: String)
    case project(workspaceID: String, id: String)
    /// Índice em `configs`: é como o resto do app endereça a bancada na tela.
    case workbench(index: Int)
    /// Cabeçalho das bancadas cujo projeto não existe. Não deveria acontecer
    /// depois da conciliação, mas o arquivo é editável e a barra não pode
    /// esconder bancada nenhuma.
    case orphans
}

/// Workspaces → projetos → bancadas, achatado para a barra.
///
/// A lista de bancadas continua plana e indexada por posição — é o que
/// `main.swift` e o socket usam; a árvore é só o jeito de olhar para ela.
struct WorkspaceTree {
    let workspaces: [WorkspaceConfig]
    let workbenches: [WorkbenchConfig]

    init(workspaces: [WorkspaceConfig], workbenches: [WorkbenchConfig]) {
        self.workspaces = workspaces
        self.workbenches = workbenches
    }

    private var knownProjects: Set<String> {
        Set(workspaces.flatMap { $0.projects.map(\.id) })
    }

    func indices(inProject id: String) -> [Int] {
        workbenches.indices.filter { workbenches[$0].project == id }
    }

    func indices(inWorkspace id: String) -> [Int] {
        guard let space = workspaces.first(where: { $0.id == id }) else { return [] }
        let ids = Set(space.projects.map(\.id))
        return workbenches.indices.filter { workbenches[$0].project.map(ids.contains) ?? false }
    }

    var orphans: [Int] {
        let known = knownProjects
        return workbenches.indices.filter { workbenches[$0].project.map { !known.contains($0) } ?? true }
    }

    var rows: [SidebarItem] {
        var out: [SidebarItem] = []
        for space in workspaces {
            out.append(.workspace(id: space.id))
            guard !space.isCollapsed else { continue }
            for project in space.projects {
                out.append(.project(workspaceID: space.id, id: project.id))
                guard !project.isCollapsed else { continue }
                out += indices(inProject: project.id).map { .workbench(index: $0) }
            }
        }
        let lost = orphans
        if !lost.isEmpty {
            out.append(.orphans)
            out += lost.map { .workbench(index: $0) }
        }
        return out
    }

    /// Quem esconde a bancada `index` quando recolhido — o projeto e o workspace
    /// dela. Serve para abrir o caminho até uma bancada ativada por fora.
    func ancestors(of index: Int) -> (workspaceID: String, projectID: String)? {
        guard index >= 0, index < workbenches.count, let pid = workbenches[index].project else { return nil }
        for space in workspaces where space.project(withID: pid) != nil {
            return (space.id, pid)
        }
        return nil
    }
}
