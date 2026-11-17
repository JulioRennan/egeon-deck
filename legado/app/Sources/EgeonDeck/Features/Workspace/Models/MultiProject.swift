import Foundation

/// Um multi-projeto como o formulário o vê: nome e as pastas escolhidas.
///
/// Por pasta, e não por id, porque a pasta pode ter acabado de entrar no
/// formulário e ainda não ser projeto nenhum. O id só é resolvido ao salvar.
struct MultiProjectDraft: Equatable {
    /// Nil = nasce agora.
    var id: String?
    var name: String
    var folders: [String]

    /// "nexus-web-app + nexus-backend" — o que a linha do formulário e o
    /// subtítulo da barra mostram.
    var summary: String {
        folders.map { URL(fileURLWithPath: ProjectConfig.normalize($0)).lastPathComponent }
            .joined(separator: " + ")
    }
}

enum MultiProject {
    /// Os rascunhos de um workspace salvo, para abrir o formulário.
    static func drafts(of space: WorkspaceConfig) -> [MultiProjectDraft] {
        space.projects.filter(\.isMulti).map { project in
            MultiProjectDraft(id: project.id, name: project.name,
                              folders: space.members(of: project).map(\.path))
        }
    }

    /// Nome de cada link dentro da pasta do multi-projeto: o da pasta do
    /// repositório, que é como o agente e o `cwd` relativo o chamam. Dois repos
    /// com a mesma pasta em lugares diferentes ganham sufixo em vez de um
    /// engolir o outro.
    static func linkNames(for members: [ProjectConfig]) -> [(name: String, target: String)] {
        var taken: Set<String> = []
        return members.map { member in
            let base = member.url.lastPathComponent
            var name = base
            var n = 2
            while taken.contains(name) { name = "\(base)-\(n)"; n += 1 }
            taken.insert(name)
            return (name, member.url.path)
        }
    }

    /// Onde a bancada em worktree de um multi-projeto mora:
    /// `<pai comum>/worktrees/<multi-projeto>/<branch>/`, com uma worktree por
    /// repositório dentro, cada uma com o nome do link.
    ///
    /// O nível do multi-projeto existe porque `worktrees/<repo>/` já é das
    /// worktrees de um repo só (ADR-022): uma branch com nome de repositório
    /// cairia dentro das dele.
    static func worktreeRoot(project: ProjectConfig, members: [ProjectConfig],
                             branch: String) -> String {
        URL(fileURLWithPath: commonParent(members.map(\.url.path)))
            .appendingPathComponent("worktrees")
            .appendingPathComponent(Worktree.sanitize(project.name))
            .appendingPathComponent(Worktree.sanitize(branch))
            .path
    }

    /// A branch de cada repositório: a da bancada, salvo a que você trocou.
    ///
    /// A raiz e o nome da bancada são sempre da branch da bancada — é ela que
    /// dá nome ao conjunto. O repo com branch própria muda só a worktree dele, e
    /// a subpasta continua com o nome do repo, para o `cwd` relativo dos nós
    /// valer igual.
    static func branches(for links: [String], workbench: String,
                         overrides: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: links.map { link in
            let custom = overrides[link]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (link, custom.isEmpty ? workbench : custom)
        })
    }

    /// O pai comum mais fundo. Sem nenhum além da raiz — repos em volumes
    /// diferentes —, o do primeiro: mandar a worktree para `/` não serve a
    /// ninguém, e o primeiro é o que você escolheu primeiro.
    static func commonParent(_ paths: [String]) -> String {
        let parents = paths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().pathComponents }
        guard var common = parents.first else { return NSHomeDirectory() }
        for other in parents.dropFirst() {
            common = Array(zip(common, other).prefix { $0 == $1 }.map(\.0))
        }
        guard common.count > 1 else {
            return URL(fileURLWithPath: paths[0]).deletingLastPathComponent().path
        }
        return NSString.path(withComponents: common)
    }
}

/// O que salvar o formulário do workspace faz com a lista de projetos.
///
/// Pura, para testar sem tela: quem é projeto de pasta, quem é multi-projeto e
/// o que fica porque tem bancada dentro. `linkPath` diz onde mora a pasta de
/// links de um multi-projeto novo, e `hasWorkbenches` é a árvore.
enum WorkspaceEdit {
    struct Outcome: Equatable {
        var projects: [ProjectConfig]
        /// Tirados no formulário, mas com bancada dentro: ficam.
        var refused: [String]
    }

    static func apply(to existing: [ProjectConfig], folders: [String],
                      multis: [MultiProjectDraft], linkPath: (String) -> String,
                      hasWorkbenches: (String) -> Bool) -> Outcome {
        var kept: [ProjectConfig] = []
        var refused: [String] = []

        // Pasta que já era projeto mantém o id — é ele que as bancadas guardam.
        // Pasta tirada com bancada dentro fica: senão a bancada viraria órfã
        // sem você ter pedido isso.
        let wantedMultis = Set(multis.compactMap(\.id))
        for project in existing {
            let wanted = project.isMulti
                ? wantedMultis.contains(project.id)
                : folders.contains { project.owns(path: $0) }
            if wanted {
                kept.append(project)
            } else if hasWorkbenches(project.id) {
                kept.append(project)
                refused.append(project.name)
            }
        }
        for folder in folders where !kept.contains(where: { !$0.isMulti && $0.owns(path: folder) }) {
            kept.append(ProjectConfig.forFolder(folder))
        }

        func memberIDs(_ draft: MultiProjectDraft) -> [String] {
            draft.folders.compactMap { folder in
                kept.first { !$0.isMulti && $0.owns(path: folder) }?.id
            }
        }
        for draft in multis {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let id = draft.id, let i = kept.firstIndex(where: { $0.id == id }) {
                kept[i].name = name.isEmpty ? kept[i].name : name
                kept[i].members = memberIDs(draft)
            } else {
                let id = WorkbenchConfig.newID()
                kept.append(ProjectConfig(id: id, name: name.isEmpty ? draft.summary : name,
                                          path: linkPath(id), members: memberIDs(draft)))
            }
        }
        return Outcome(projects: kept, refused: refused)
    }
}
