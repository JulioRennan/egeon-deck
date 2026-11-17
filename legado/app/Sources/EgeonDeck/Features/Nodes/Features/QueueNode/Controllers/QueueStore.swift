import AppKit

/// O disco de uma fila: `workbenches/<bancada>/queues/<nó>/queue.json`, com as
/// imagens ao lado. Na pasta da bancada porque é dela, como o chat e a trilha
/// (ADR-036); por nó porque cada fila é um card.
struct QueueStore {
    let folder: URL

    init(folder: URL) { self.folder = folder }

    init(workbenchID: String, nodeID: String) {
        folder = Flavor.current.workbenchesDirectory
            .appendingPathComponent(workbenchID)
            .appendingPathComponent("queues")
            .appendingPathComponent(nodeID)
    }

    private var file: URL { folder.appendingPathComponent("queue.json") }

    func load() -> PromptQueue {
        guard let data = try? Data(contentsOf: file) else { return PromptQueue() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(PromptQueue.self, from: data)) ?? PromptQueue()
    }

    func save(_ queue: PromptQueue) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encoder.encode(queue).write(to: file, options: .atomic)
        } catch {
            Log.write("fila: não gravei \(file.path) — \(error)")
        }
    }

    func url(of image: String) -> URL { folder.appendingPathComponent(image) }

    /// Grava o PNG e devolve o nome dele na pasta.
    func saveImage(png data: Data) -> String? {
        let name = "img-\(UUID().uuidString.prefix(8).lowercased()).png"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url(of: name), options: .atomic)
            return name
        } catch {
            Log.write("fila: não gravei a imagem — \(error)")
            return nil
        }
    }

    /// Copia para dentro da pasta: o arquivo arrastado pode sumir (print na
    /// mesa, download temporário) antes de o item ser enviado.
    func importImage(at source: URL) -> String? {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let name = "img-\(UUID().uuidString.prefix(8).lowercased()).\(ext)"
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: url(of: name))
            return name
        } catch {
            Log.write("fila: não copiei \(source.path) — \(error)")
            return nil
        }
    }

    func remove(images: [String]) {
        for name in images { try? FileManager.default.removeItem(at: url(of: name)) }
    }

    func removeAll() { try? FileManager.default.removeItem(at: folder) }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]

    /// O que dá para tirar de um pasteboard como imagem: arquivos de imagem
    /// (Finder, arrasto) ou a imagem em si (print com ⌃⇧⌘4, cópia do navegador).
    enum Pasted {
        case files([URL])
        case png(Data)
    }

    static func images(in pasteboard: NSPasteboard) -> Pasted? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            let images = urls.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            if !images.isEmpty { return .files(images) }
            if !urls.isEmpty { return nil }
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        return .png(png)
    }
}
