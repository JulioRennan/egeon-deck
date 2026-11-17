import AppKit

/// O que um arrasto do macOS trouxe, traduzido para o que se digita num terminal:
/// caminhos de arquivo.
///
/// Existe porque o SwiftTerm não é destino de arrasto — soltar uma imagem sobre o
/// terminal não fazia nada, e a única forma de dar um arquivo ao agente era
/// descobrir o caminho dele à mão e digitar.
enum TerminalDrop {
    static let types: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]

    private static let urlOptions: [NSPasteboard.ReadingOptionKey: Any] =
        [.urlReadingFileURLsOnly: true]

    /// Se vale aceitar o arrasto. Separado de `text(from:)` porque aquele grava em
    /// disco a imagem que veio sem arquivo, e isto é chamado a cada quadro
    /// enquanto o cursor passa por cima.
    static func accepts(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSURL.self], options: urlOptions)
            || pasteboard.availableType(from: [.png, .tiff]) != nil
    }

    /// Texto para injetar, ou `nil` se o arrasto não trouxe nada aproveitável.
    static func text(from pasteboard: NSPasteboard) -> String? {
        var caminhos = fileURLs(in: pasteboard).map(\.path)
        // Imagem arrastada de dentro do navegador não tem arquivo do lado de cá:
        // vem como PNG ou TIFF cru. Sem gravar em disco não existe caminho para
        // escrever no terminal, e a imagem se perderia no caminho.
        if caminhos.isEmpty, let salva = savedImage(from: pasteboard) {
            caminhos = [salva.path]
        }
        guard !caminhos.isEmpty else { return nil }
        // Espaço no fim: o cursor fica pronto para a frase que acompanha o
        // arquivo, que é o motivo de você tê-lo arrastado até aqui.
        return caminhos.map(quoted).joined(separator: " ") + " "
    }

    private static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: urlOptions) as? [URL] ?? []
    }

    private static func savedImage(from pasteboard: NSPasteboard) -> URL? {
        let png: Data?
        if let dados = pasteboard.data(forType: .png) {
            png = dados
        } else if let tiff = pasteboard.data(forType: .tiff) {
            png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        } else {
            png = nil
        }
        guard let dados = png else { return nil }

        // Rascunho, e não configuração: `~/.egeon` é feito para ser aberto e
        // editado à mão, e PNG despejado ali só atrapalha quem for ler.
        let pasta = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Flavor.current.identifier)-drop", isDirectory: true)
        // Milissegundos, e não segundos: duas imagens arrastadas em seguida
        // ganhariam o mesmo nome, e a segunda apagaria a primeira antes de o
        // agente ter lido qualquer uma.
        let nome = "drop-\(Int(Date().timeIntervalSince1970 * 1000)).png"
        do {
            try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
            let arquivo = pasta.appendingPathComponent(nome)
            try dados.write(to: arquivo)
            return arquivo
        } catch {
            Log.write("drop: imagem sem arquivo não pôde ser gravada: \(error)")
            return nil
        }
    }

    /// Caminho como se digita: só ganha aspas quando precisa delas.
    ///
    /// Citar sempre seria mais simples, mas do outro lado nem sempre há shell —
    /// num terminal com IA o caminho é lido por um modelo, e `'…'` em volta é
    /// ruído que não protege nada. Sem espaço nem caractere de shell, vai cru.
    static func quoted(_ path: String) -> String {
        let seguros = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-./@%+=:,")
        if !path.isEmpty, path.unicodeScalars.allSatisfy(seguros.contains) { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
