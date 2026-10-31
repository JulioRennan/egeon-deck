import Foundation

/// Do zip baixado ao bundle pronto ao lado do app, e daí à troca.
struct UpdateInstaller {
    enum Failure: Error, Equatable, CustomStringConvertible {
        case badSignature
        case notInstallable(String)
        case wrongApp(String)
        case notNewer(String)
        case badCodeSignature
        case cannotWrite(String)

        var description: String {
            switch self {
            case .badSignature: return "a assinatura do download não confere"
            case .notInstallable(let why): return "o download não é um app válido (\(why))"
            case .wrongApp(let id): return "o download é de outro app (\(id))"
            case .notNewer(let version): return "o download traz a versão \(version), que não é mais nova"
            case .badCodeSignature: return "a assinatura de código do app baixado está quebrada"
            case .cannotWrite(let path): return "sem permissão para escrever em \(path)"
            }
        }
    }

    /// O app instalado — `Bundle.main` em uso.
    let destination: URL
    let bundleID: String
    let installedVersion: String
    var publicKey = UpdateSignature.publicKey

    /// Ao lado do destino: no mesmo volume o `mv` é instantâneo. Sem `.app` no nome
    /// de propósito, para não virar uma segunda cópia que o Spotlight abre.
    var staged: URL { URL(fileURLWithPath: destination.path + ".novo") }

    /// App rodando translocado, ou em pasta sem escrita, não tem como se trocar.
    var canInstall: Bool {
        !destination.path.contains("/AppTranslocation/")
            && FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path)
    }

    /// Confere tudo e deixa o bundle em `staged`. Devolve a versão preparada.
    @discardableResult
    func prepare(zip: Data, signature: String) throws -> String {
        guard UpdateSignature.isValid(zip, signature: signature, publicKey: publicKey) else {
            throw Failure.badSignature
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("egeon-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let archive = work.appendingPathComponent("update.zip")
        try zip.write(to: archive)
        let unpacked = work.appendingPathComponent("x")
        // `ditto`, e não unzip: preserva a assinatura de código do bundle.
        guard Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, unpacked.path]) == 0 else {
            throw Failure.notInstallable("não descompactou")
        }
        let apps = (try? fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "app" } ?? []
        guard apps.count == 1, let app = apps.first,
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let id = info["CFBundleIdentifier"] as? String,
              let version = info["CFBundleShortVersionString"] as? String else {
            throw Failure.notInstallable("sem bundle dentro")
        }
        guard id == bundleID else { throw Failure.wrongApp(id) }
        // A assinatura vale para qualquer zip já publicado: sem esta conta, servir
        // uma versão antiga e com falha passaria como atualização.
        guard let mine = AppVersion(installedVersion), let theirs = AppVersion(version), theirs > mine else {
            throw Failure.notNewer(version)
        }
        guard Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) == 0 else {
            throw Failure.badCodeSignature
        }
        discardStaged()
        // Do temporário para o destino pode cruzar volume: `ditto` copia, e o `mv`
        // da troca é que precisa ser no mesmo volume.
        guard Self.run("/usr/bin/ditto", [app.path, staged.path]) == 0 else {
            throw Failure.cannotWrite(destination.deletingLastPathComponent().path)
        }
        return version
    }

    func discardStaged() { try? FileManager.default.removeItem(at: staged) }

    var isStaged: Bool { FileManager.default.fileExists(atPath: staged.path) }

    /// Solta o script e volta: ele espera `pid` sair para fazer a troca.
    func launchSwap(pid: Int32, reopen: Bool, log: URL) throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("egeon-update-\(UUID().uuidString).sh")
        try UpdateSwapScript.body.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(pid), staged.path, destination.path, reopen ? "1" : "0"]
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        try process.run()
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
