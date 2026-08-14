import Foundation

/// Ambiente entregue aos subprocessos: terminais, agentes e o code-server.
///
/// Existe porque um app lançado pelo Finder não herda o shell de ninguém — ele
/// recebe o PATH mínimo do launchd. E `zsh -lc` não resolve: o `.zshrc`, onde a
/// maioria dos instaladores põe seus diretórios, só é lido em shell interativo.
///
/// O sintoma é sempre o mesmo e sempre confuso: um binário que funciona no
/// Terminal vira "command not found" aqui. Já aconteceu com o `claude`; com o
/// `flutter` sob fvm o efeito é a extensão Dart do editor não achar o SDK e o
/// debug de Flutter simplesmente não subir.
enum AppEnvironment {

    /// Diretórios que instaladores usam e que o launchd não conhece. Ordem
    /// importa: entram na frente, então o que o usuário instalou ganha da versão
    /// que vem com o sistema.
    private static var candidates: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin",
            // Flutter e Dart sob fvm, e binários instalados via `dart pub global`.
            "\(home)/fvm/default/bin",
            "\(home)/.pub-cache/bin",
            // adb e companhia: a extensão Flutter lista dispositivos Android por aqui.
            "\(home)/Library/Android/sdk/platform-tools",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin"
        ]
    }

    static func enrichedPath(_ current: String?) -> String {
        var parts = (current ?? "").split(separator: ":").map(String.init)
        for path in candidates.reversed() where !parts.contains(path) {
            if FileManager.default.fileExists(atPath: path) { parts.insert(path, at: 0) }
        }
        return parts.joined(separator: ":")
    }

    /// Aspas simples para a linha de comando, escapando as próprias aspas.
    ///
    /// O comando do terminal é montado como string e entregue a `zsh -lc`, então
    /// um papel com aspas, `$` ou `;` quebraria o arranque — ou, pior, executaria
    /// outra coisa.
    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Ambiente completo para um processo filho.
    ///
    /// As variáveis `CLAUDE_CODE*` saem porque, herdadas, fazem um agente aberto
    /// aqui se julgar sessão filha de outro — e desligar transcript, entre outras
    /// esquisitices.
    static func forChildProcess() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
            .filter { !$0.key.hasPrefix("CLAUDE_CODE") && $0.key != "CLAUDECODE" }
        // Na frente de tudo: o `egeon` é do flavor que lançou este processo, e
        // um homônimo em /usr/local/bin faria o agente do dev falar com o socket
        // do estável.
        environment["PATH"] = EgeonCLI.directory.path + ":"
            + enrichedPath(environment["PATH"])
        return environment
    }
}
