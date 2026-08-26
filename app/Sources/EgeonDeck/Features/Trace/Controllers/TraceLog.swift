import Foundation

/// Grava a trilha da bancada: UM Markdown por bancada, em
/// `workbenches/<id>/trace.md` dentro do diretório do flavor (ADR-036).
///
/// Um arquivo só, e não um por agente, porque o uso é auditar a bancada:
/// ler de cima a baixo quem fez o quê, em ordem, sem cruzar arquivos. A pasta
/// é o `id` da bancada e não o nome: nome se repete (apagou, recriou) e muda
/// (renomeou); a trilha segue a bancada, não o rótulo. O nome fica no
/// cabeçalho do arquivo, que é onde você o lê. Fora do repositório do projeto
/// porque a bancada abre worktrees, e um arquivo dentro delas apareceria no
/// `git status` de cada uma.
final class TraceLog {
    static let shared = TraceLog(workbenches: Flavor.current.workbenchesDirectory)

    let workbenches: URL
    private let queue: DispatchQueue

    init(workbenches: URL) {
        self.workbenches = workbenches
        self.queue = DispatchQueue(label: "\(Flavor.current.identifier).trace")
    }

    func directory(forWorkbench id: String) -> URL {
        workbenches.appendingPathComponent(id)
    }

    func file(for entry: TraceEntry) -> URL {
        current(forWorkbench: entry.workbenchID)
    }

    func current(forWorkbench id: String) -> URL {
        directory(forWorkbench: id).appendingPathComponent(Self.currentName)
    }

    func archiveDirectory(forWorkbench id: String) -> URL {
        directory(forWorkbench: id).appendingPathComponent(Self.archiveName)
    }

    /// As trilhas arquivadas, da mais antiga para a mais nova.
    func archived(forWorkbench id: String) -> [URL] {
        let dir = archiveDirectory(forWorkbench: id)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// "Limpar a bancada" leva a trilha junto com o chat: `trace.md` vai para
    /// `trace-archive/trace-<início>_<fim>.md` e a próxima entrada abre outro,
    /// com cabeçalho novo. O período sai das datas do próprio arquivo — nasce
    /// na primeira entrada e é tocado na última — porque o carimbo de cada
    /// registro só tem minuto. Nil se não há trilha: nada nasce vazio.
    @discardableResult
    func archive(workbench id: String, at now: Date = Date()) -> URL? {
        queue.sync {
            let file = current(forWorkbench: id)
            let fm = FileManager.default
            guard let attributes = try? fm.attributesOfItem(atPath: file.path) else { return nil }
            let dir = archiveDirectory(forWorkbench: id)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let start = attributes[.creationDate] as? Date ?? now
            let end = attributes[.modificationDate] as? Date ?? now
            let stamp = Self.clock.string(from: start) + "_" + Self.clock.string(from: max(start, end))
            var target = dir.appendingPathComponent(Self.prefix + stamp + Self.suffix)
            // Mesmo período duas vezes: sufixo, não sobrescrita. `_` e não `-`
            // pelo mesmo motivo do chat — ordena depois de `.`.
            var n = 2
            while fm.fileExists(atPath: target.path) {
                target = dir.appendingPathComponent(Self.prefix + stamp + "_\(n)" + Self.suffix)
                n += 1
            }
            do {
                try fm.moveItem(at: file, to: target)
            } catch {
                Log.write("trace[\(id)]: não consegui arquivar \(file.lastPathComponent) — \(error)")
                return nil
            }
            return target
        }
    }

    func record(_ entry: TraceEntry) {
        queue.async { [self] in
            let url = file(for: entry)
            let manager = FileManager.default
            try? manager.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
            var text = entry.markdown
            if !manager.fileExists(atPath: url.path) {
                text = Self.header(workbench: entry.workbench, id: entry.workbenchID) + text
            }
            if let handle = FileHandle(forWritingAtPath: url.path) {
                handle.seekToEndOfFile()
                handle.write(Data(text.utf8))
                try? handle.close()
                Log.write("trace[\(entry.address)]: registrado")
            } else if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                Log.write("trace[\(entry.address)]: registrado")
            } else {
                Log.write("trace[\(entry.address)]: não consegui escrever \(url.path)")
            }
        }
    }

    /// Espera o que já foi pedido terminar de gravar. Existe para teste.
    func flush() { queue.sync {} }

    static let currentName = "trace.md"
    static let archiveName = "trace-archive"
    private static let prefix = "trace-"
    private static let suffix = ".md"

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    /// O nome da bancada no momento em que a trilha nasceu, e o id que a
    /// identifica de verdade — é ele que nomeia a pasta.
    static func header(workbench: String, id: String) -> String {
        """
        # \(workbench)
        bancada `\(id)`

        Trilha da bancada: cada agente registra, ao fim do turno, o que foi pedido
        e o que entregou (`egeon trace`); o terminal comum registra cada comando.
        Quem escreveu, CLI, modelo e conversa são carimbados pelo Egeon Deck.


        """
    }
}
