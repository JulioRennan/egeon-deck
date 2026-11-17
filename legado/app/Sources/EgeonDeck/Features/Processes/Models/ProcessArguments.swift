import Foundation

/// A linha de comando e o ambiente de um processo, do buffer do
/// `KERN_PROCARGS2`: `argc` em 4 bytes, o caminho do executável, zeros de
/// alinhamento, os `argc` argumentos e então o ambiente, tudo separado por NUL.
struct ProcessArguments: Equatable {
    var arguments: [String] = []
    var environment: [String: String] = [:]

    init(arguments: [String] = [], environment: [String: String] = [:]) {
        self.arguments = arguments
        self.environment = environment
    }

    init?(procargs data: Data) {
        guard data.count >= 4 else { return nil }
        let argc = data.prefix(4).withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        let bytes = [UInt8](data.dropFirst(4))
        var index = 0

        func next() -> String? {
            guard index < bytes.count else { return nil }
            let end = bytes[index...].firstIndex(of: 0) ?? bytes.count
            let text = String(decoding: bytes[index..<end], as: UTF8.self)
            index = end + 1
            return text
        }

        guard next() != nil else { return nil }
        while index < bytes.count, bytes[index] == 0 { index += 1 }
        for _ in 0..<max(0, argc) {
            guard let argument = next() else { break }
            arguments.append(argument)
        }
        // O ambiente termina na primeira string vazia; o que vem depois é a
        // área de strings do kernel (o `apple[]`), que não é do processo.
        while let entry = next(), !entry.isEmpty {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
    }
}
