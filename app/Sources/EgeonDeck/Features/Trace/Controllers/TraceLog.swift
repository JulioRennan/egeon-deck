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
        directory(forWorkbench: entry.workbenchID).appendingPathComponent("trace.md")
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
