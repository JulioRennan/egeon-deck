import Foundation

/// O que o "Novo projeto…" faz no disco: a pasta e, se pedido, o `git init`.
enum ProjectFolder {
    struct Failure: Error, LocalizedError {
        var errorDescription: String?
    }

    /// Pasta adotada que já é repositório fica como está: `git init` por cima
    /// de um repositório não estraga nada, mas também não tem o que fazer.
    static func materialize(_ plan: NewProject.Plan, git: Bool) throws {
        let url = URL(fileURLWithPath: ProjectConfig.normalize(plan.path))
        if plan.create {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        guard git, !FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
        else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git", "init", "--quiet"]
        task.currentDirectoryURL = url
        task.environment = AppEnvironment.forChildProcess()
        // Nada de `Pipe`: a ponta de escrita é herdada por quem o app lançar no
        // meio, e a leitura só acaba quando todas fecham (ver `Worktree.run`).
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw Failure(errorDescription: "git init saiu com \(task.terminationStatus) em \(plan.path)")
        }
    }
}
