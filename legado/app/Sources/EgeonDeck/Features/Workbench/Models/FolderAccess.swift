import Foundation

/// O app consegue LER a pasta da bancada?
///
/// `fileExists` responde sim para pasta que o macOS bloqueou: o bloqueio é da
/// privacidade (Documentos, Mesa, Transferências), e ele só aparece ao listar.
/// Sem esta conferência a bancada abria normal e o agente morria no arranque com
/// "possibly due to low max file descriptors" — a mensagem genérica do Claude
/// Code para o EPERM que ele não esperava.
///
/// Ler a pasta é também o que faz o macOS perguntar quando ainda não há decisão:
/// conferir na criação traz o pedido de permissão para a hora em que você
/// escolheu a pasta, e não para o primeiro agente.
enum FolderAccess: Equatable {
    case ok
    case missing
    /// Existe, mas o sistema não deixa ler. `folder` é a pasta protegida do
    /// macOS por cima dela, quando é uma delas.
    case denied(folder: String?)

    static func check(_ url: URL) -> FolderAccess {
        guard let dir = opendir(url.path) else {
            switch errno {
            case ENOENT, ENOTDIR: return .missing
            case EPERM, EACCES:   return .denied(folder: protectedFolder(of: url.path))
            default:              return .ok
            }
        }
        closedir(dir)
        return .ok
    }

    /// Confere e, se o macOS recusou uma pasta protegida, pede de novo.
    ///
    /// Recusa é permanente para o macOS: ele não pergunta outra vez sozinho. O
    /// `tccutil reset` da própria pasta, do próprio app — sem senha, medido —
    /// volta a decisão para "não perguntado", e a leitura seguinte faz o pedido
    /// aparecer. Bloqueia até você responder: chamar fora da main.
    static func request(_ url: URL) -> FolderAccess {
        let first = check(url)
        guard case .denied(let folder?) = first, let service = service(of: folder),
              let bundle = Bundle.main.bundleIdentifier,
              Bundle.main.bundleURL.pathExtension == "app" else { return first }
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", service, bundle]
        reset.standardOutput = FileHandle.nullDevice
        reset.standardError = FileHandle.nullDevice
        guard (try? reset.run()) != nil else { return first }
        reset.waitUntilExit()
        return check(url)
    }

    /// O serviço do TCC de cada pasta protegida.
    static func service(of folder: String) -> String? {
        ["Documentos": "SystemPolicyDocumentsFolder", "Mesa": "SystemPolicyDesktopFolder",
         "Transferências": "SystemPolicyDownloadsFolder"][folder]
    }

    /// O nome como o Ajustes mostra, para o aviso dizer o que ligar.
    static func protectedFolder(of path: String, home: String = NSHomeDirectory()) -> String? {
        let folders = [("Documents", "Documentos"), ("Desktop", "Mesa"), ("Downloads", "Transferências")]
        let standardized = (path as NSString).standardizingPath
        return folders.first { name, _ in
            let root = (home as NSString).appendingPathComponent(name)
            return standardized == root || standardized.hasPrefix(root + "/")
        }?.1
    }

    /// O aviso para quem abriu a bancada. `nil` quando dá para ler.
    var message: String? {
        guard case .denied(let folder) = self else { return nil }
        let place = folder.map { "a pasta \($0)" } ?? "esta pasta"
        return "Sem acesso a \(place): libere o Egeon Deck em Ajustes › Privacidade › Arquivos e Pastas."
    }

    static let settingsURL = URL(string:
        "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!
}
