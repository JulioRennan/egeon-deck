import Foundation

/// Qual cópia do app está rodando.
///
/// Existe para o app poder ser desenvolvido enquanto é usado: o estável segura os
/// seus agentes de verdade, e o dev é o que eu derrubo e reconstruo. Sem isso todo
/// rebuild mata a bancada em que você está trabalhando — foi assim a bancada
/// inteira em que isto foi construído.
///
/// Resolvido do bundle e não de flag de compilação: é um binário só, e o que muda
/// é o Info.plist que o `make.sh` escreve. Trocar de flavor não recompila nada.
enum Flavor {
    case stable
    case dev

    /// Sufixo do bundle id que marca o dev. `dev.duckcoder.egeondeck.dev`.
    private static let devSuffix = ".dev"

    static let current: Flavor = {
        let id = Bundle.main.bundleIdentifier ?? ""
        // Rodando por `swift run`, sem bundle, assume estável: é o menos
        // surpreendente, e evita que um teste solto escreva no diretório do dev.
        return id.hasSuffix(devSuffix) ? .dev : .stable
    }()

    var isDev: Bool { self == .dev }

    var displayName: String {
        switch self {
        case .stable: return "Egeon Deck"
        case .dev:    return "Egeon Deck (dev)"
        }
    }

    /// Tudo que o app guarda. Separado por flavor de propósito: com um diretório
    /// só, o dev subiria os MESMOS terminais do estável nas mesmas pastas, e os
    /// dois brigariam para gravar o workbenches.json.
    var configDirectory: URL {
        URL(fileURLWithPath: NSString(string: isDev ? "~/.egeon-dev" : "~/.egeon")
            .expandingTildeInPath)
    }

    func config(_ name: String) -> URL { configDirectory.appendingPathComponent(name) }

    var logPath: String {
        NSString(string: isDev ? "~/egeon-dev.log" : "~/egeon.log").expandingTildeInPath
    }

    /// Uma porta por flavor. Sem isto o segundo a subir encontraria a porta
    /// tomada, concluiria que é um code-server órfão da execução anterior — que é
    /// o caso comum — e mataria o do outro app.
    var codeServerPort: Int { isDev ? 8392 : 8391 }

    /// Prefixo de rótulo de fila e afins, para os dois processos se distinguirem
    /// em ferramenta de diagnóstico.
    var identifier: String { isDev ? "egeon-dev" : "egeon" }
}
