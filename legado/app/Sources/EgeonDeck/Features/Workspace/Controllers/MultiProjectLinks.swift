import Foundation

/// Mantém a pasta de um multi-projeto com um link por repositório.
///
/// Link, e não cópia nem worktree: no checkout principal o que se quer é o
/// repositório de verdade, só que ao lado do outro. O isolamento de branch é
/// da bancada em worktree, que tem pasta própria (ADR-065).
enum MultiProjectLinks {
    /// Deixa `directory` com exatamente estes links. Só apaga o que é link: um
    /// arquivo que você pôs ali à mão não é do app.
    @discardableResult
    static func sync(_ directory: URL, links: [(name: String, target: String)]) -> [String] {
        let fm = FileManager.default
        var problems: [String] = []
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return ["não consegui criar \(directory.path) — \(error)"]
        }

        let wanted = Dictionary(links.map { ($0.name, $0.target) }, uniquingKeysWith: { a, _ in a })
        for entry in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? [] {
            let url = directory.appendingPathComponent(entry)
            guard let current = try? fm.destinationOfSymbolicLink(atPath: url.path) else { continue }
            if wanted[entry] != current { try? fm.removeItem(at: url) }
        }
        for (name, target) in links {
            let url = directory.appendingPathComponent(name)
            if (try? fm.destinationOfSymbolicLink(atPath: url.path)) == target { continue }
            guard !fm.fileExists(atPath: url.path) else {
                problems.append("\(url.path) já existe e não é link — deixei como está")
                continue
            }
            do { try fm.createSymbolicLink(atPath: url.path, withDestinationPath: target) }
            catch { problems.append("link \(name) → \(target): \(error)") }
        }
        return problems
    }

    /// Todos os multi-projetos dos workspaces, de uma vez: na carga e depois de
    /// salvar o formulário.
    static func syncAll(_ workspaces: [WorkspaceConfig]) {
        for space in workspaces {
            for project in space.projects where project.isMulti {
                let problems = sync(project.url, links: MultiProject.linkNames(for: space.members(of: project)))
                problems.forEach { Log.write("multi-projeto \"\(project.name)\": \($0)") }
            }
        }
    }
}

extension MultiProjectLinks {
    /// Subpastas de verdade, sem os links: é onde moram as worktrees de uma
    /// bancada multi-projeto.
    static func realSubfolders(of directory: URL) -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? []).sorted().compactMap { entry in
            let path = directory.appendingPathComponent(entry).path
            guard (try? fm.destinationOfSymbolicLink(atPath: path)) == nil else { return nil }
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue ? path : nil
        }
    }

    /// Apaga a pasta-mãe quando só sobraram links e lixo do Finder nela. Com
    /// qualquer outra coisa dentro — worktree que resistiu, arquivo seu — fica.
    static func pruneRoot(_ directory: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        let entries = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        let disposable = entries.allSatisfy { entry in
            entry == ".DS_Store"
                || (try? fm.destinationOfSymbolicLink(atPath: directory.appendingPathComponent(entry).path)) != nil
        }
        guard disposable else { return }
        do {
            try fm.removeItem(at: directory)
            Log.write("multi-projeto: pasta \(directory.path) apagada")
        } catch {
            Log.write("multi-projeto: não consegui apagar \(directory.path) — \(error)")
        }
    }
}
