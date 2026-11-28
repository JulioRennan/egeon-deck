// O mínimo do app que os modelos portados referenciam. O oráculo só decodifica
// e recodifica; nada aqui toca em disco.
import Foundation

enum Log {
    static func write(_ message: String, key: String? = nil) {}
}

struct Flavor {
    static let current = Flavor()
    /// `ORACULO_HOME` aponta para uma pasta de trabalho do oráculo: é onde o
    /// `ShellHook` e o `AgentStore` gravam, no lugar de `~/.egeon`.
    func config(_ name: String) -> URL {
        let home = ProcessInfo.processInfo.environment["ORACULO_HOME"] ?? "/nao-usado"
        return URL(fileURLWithPath: home).appendingPathComponent(name)
    }
    func workspaceDirectory(_ id: String) -> URL { URL(fileURLWithPath: "/nao-usado/workspaces/\(id)") }
}

struct ActivitySummary {
    var starting = 0, working = 0, background = 0, attention = 0, done = 0, failed = 0, retrying = 0
}

/// O arquivo de hooks do Claude Code: só o caminho entra na linha de comando.
enum ClaudeHooks {
    static var settingsFile: URL { URL(fileURLWithPath: "/oraculo/claude-hooks.json") }
}
