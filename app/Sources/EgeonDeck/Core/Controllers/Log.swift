import Foundation

/// Log em arquivo. O app roda via LaunchServices (`open`), então stdout se
/// perde — sem isso não dá pra saber por que um portal ficou parado.
enum Log {
    static let path = Flavor.current.logPath

    private static let queue = DispatchQueue(label: "\(Flavor.current.identifier).log")
    private static var lastMessage: [String: String] = [:]

    static func reset() {
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// `key` deduplica: um tick de 0.25s repetindo o mesmo erro viraria spam.
    static func write(_ message: String, key: String? = nil) {
        queue.async {
            if let key {
                if lastMessage[key] == message { return }
                lastMessage[key] = message
            }
            let line = "\(Date().formatted(date: .omitted, time: .standard)) \(message)\n"
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }
}
