import CryptoKit
import XCTest
@testable import EgeonDeck

final class AppUpdateTests: XCTestCase {
    func testVersionsCompareAsNumbers() throws {
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("v1.10.0")), try XCTUnwrap(AppVersion("1.9.2")))
        XCTAssertEqual(try XCTUnwrap(AppVersion("1.6")), try XCTUnwrap(AppVersion("v1.6.0")))
        XCTAssertLessThan(try XCTUnwrap(AppVersion("1.6.0")), try XCTUnwrap(AppVersion("1.6.1")))
        XCTAssertNil(AppVersion("1.6.0-beta"))
        XCTAssertNil(AppVersion("nightly"))
    }

    private func release(tag: String = "v1.7.0", assets: [String] = ["EgeonDeck.zip", "EgeonDeck.zip.sig"]) -> Data {
        let json: [String: Any] = [
            "tag_name": tag, "html_url": "https://example.com/r", "body": "novidades",
            "assets": assets.map { ["name": $0, "browser_download_url": "https://example.com/\($0)"] }]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    func testReleaseParsing() throws {
        let update = try XCTUnwrap(AvailableUpdate.parse(release: release()))
        XCTAssertEqual(update.version, "1.7.0")
        XCTAssertEqual(update.notes, "novidades")
        XCTAssertEqual(update.zip.lastPathComponent, "EgeonDeck.zip")
        XCTAssertNotNil(update.signature)
        XCTAssertTrue(update.isNewer(than: "1.6.0"))
        XCTAssertFalse(update.isNewer(than: "1.7.0"))
        XCTAssertFalse(update.isNewer(than: "1.8.0"))

        XCTAssertNil(try XCTUnwrap(AvailableUpdate.parse(release: release(assets: ["EgeonDeck.zip"]))).signature)
        XCTAssertNil(AvailableUpdate.parse(release: release(assets: ["outro.zip"])))
        XCTAssertNil(AvailableUpdate.parse(release: release(tag: "nightly")))
        XCTAssertNil(AvailableUpdate.parse(release: Data("{}".utf8)))
    }

    func testPolicyNeverDownloadsWithoutTheOptionAndPromptsOnlyAtLaunchOrOnRequest() {
        typealias P = UpdatePolicy
        XCTAssertEqual(P.action(newer: false, reason: .launch, auto: true), .nothing)
        XCTAssertEqual(P.action(newer: false, reason: .periodic, auto: false), .nothing)
        XCTAssertEqual(P.action(newer: false, reason: .manual, auto: false), .sayUpToDate)
        XCTAssertEqual(P.action(newer: true, reason: .launch, auto: false), .prompt)
        XCTAssertEqual(P.action(newer: true, reason: .periodic, auto: false), .showInMenu)
        XCTAssertEqual(P.action(newer: true, reason: .manual, auto: false), .prompt)
        XCTAssertEqual(P.action(newer: true, reason: .manual, auto: true), .prompt)
        XCTAssertEqual(P.action(newer: true, reason: .launch, auto: true), .downloadQuietly)
        XCTAssertEqual(P.action(newer: true, reason: .periodic, auto: true), .downloadQuietly)
    }

    func testPromptSaysWhatRestartingCostsAndWhatTheClickAuthorizes() {
        let many = UpdatePrompt.text(version: "1.7.0", notes: String(repeating: "x", count: 900), agents: 3)
        XCTAssertTrue(many.contains("3 agentes abertos"))
        XCTAssertTrue(many.contains("quarentena"))
        XCTAssertLessThan(many.count, 900)
        XCTAssertTrue(UpdatePrompt.text(version: "1.7.0", notes: "", agents: 1).contains("1 agente aberto"))
        XCTAssertFalse(UpdatePrompt.text(version: "1.7.0", notes: "", agents: 0).contains("agente"))
    }

    func testPublishedKeyIsAUsableKey() throws {
        let raw = try XCTUnwrap(Data(base64Encoded: UpdateSignature.publicKey))
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: raw))
    }

    // MARK: Bundle de verdade

    private var root: URL!
    private let key = Curve25519.Signing.PrivateKey()
    private var publicKey: String { key.publicKey.rawRepresentation.base64EncodedString() }
    private let bundleID = "dev.teste.egeon"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    private func tool(_ path: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func makeApp(at url: URL, version: String, id: String? = nil, sign: Bool = true) throws {
        let macos = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macos.appendingPathComponent("EgeonDeck").path)
        let info: [String: Any] = ["CFBundleIdentifier": id ?? bundleID, "CFBundleShortVersionString": version,
                                   "CFBundleExecutable": "EgeonDeck", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
        if sign { XCTAssertEqual(try tool("/usr/bin/codesign", ["--force", "--sign", "-", url.path]), 0) }
    }

    private func makeZip(version: String, id: String? = nil, tamper: Bool = false) throws -> (zip: Data, signature: String) {
        let folder = root.appendingPathComponent("pacote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let app = folder.appendingPathComponent("EgeonDeck.app")
        try makeApp(at: app, version: version, id: id)
        if tamper { try Data("adulterado".utf8).write(to: app.appendingPathComponent("Contents/MacOS/EgeonDeck")) }
        let zip = folder.appendingPathComponent("e.zip")
        XCTAssertEqual(try tool("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path]), 0)
        let data = try Data(contentsOf: zip)
        return (data, try key.signature(for: data).base64EncodedString())
    }

    private func installer() -> UpdateInstaller {
        UpdateInstaller(destination: root.appendingPathComponent("Egeon Deck.app"), bundleID: bundleID,
                        installedVersion: "1.6.0", publicKey: publicKey)
    }

    func testPrepareStagesASignedNewerApp() throws {
        let (zip, signature) = try makeZip(version: "1.7.0")
        let installer = installer()
        XCTAssertEqual(try installer.prepare(zip: zip, signature: signature), "1.7.0")
        XCTAssertTrue(installer.isStaged)
        XCTAssertEqual(installer.staged.lastPathComponent, "Egeon Deck.app.novo")
        XCTAssertEqual(try tool("/usr/bin/codesign", ["--verify", "--deep", "--strict", installer.staged.path]), 0)
    }

    func testPrepareRefusesWhatItCannotTrust() throws {
        let installer = installer()
        let good = try makeZip(version: "1.7.0")
        func refused(_ zip: Data, _ signature: String, _ expected: (UpdateInstaller.Failure) -> Bool,
                     line: UInt = #line) {
            XCTAssertThrowsError(try installer.prepare(zip: zip, signature: signature), line: line) { error in
                XCTAssertTrue(expected(error as! UpdateInstaller.Failure), "\(error)", line: line)
            }
            XCTAssertFalse(installer.isStaged, line: line)
        }

        // Um byte a mais no zip, ou assinado por outra chave.
        refused(good.zip + Data([0]), good.signature) { $0 == .badSignature }
        let stranger = try Curve25519.Signing.PrivateKey().signature(for: good.zip).base64EncodedString()
        refused(good.zip, stranger) { $0 == .badSignature }
        refused(good.zip, "isto não é base64") { $0 == .badSignature }

        // Assinado de verdade, e mesmo assim não serve.
        let old = try makeZip(version: "1.6.0")
        refused(old.zip, old.signature) { $0 == .notNewer("1.6.0") }
        let other = try makeZip(version: "1.7.0", id: "dev.outro.app")
        refused(other.zip, other.signature) { $0 == .wrongApp("dev.outro.app") }
        let tampered = try makeZip(version: "1.7.0", tamper: true)
        refused(tampered.zip, tampered.signature) { $0 == .badCodeSignature }
    }

    private func swap() throws -> (status: Int32, destination: URL, novo: URL) {
        let destination = root.appendingPathComponent("Egeon Deck.app")
        let novo = root.appendingPathComponent("Egeon Deck.app.novo")
        try makeApp(at: destination, version: "1.6.0", sign: false)
        try makeApp(at: novo, version: "1.7.0", sign: false)
        let script = root.appendingPathComponent("troca.sh")
        try UpdateSwapScript.body.write(to: script, atomically: true, encoding: .utf8)
        // Pid que já não existe: a espera passa direto.
        let status = try tool("/bin/sh", [script.path, "999999", novo.path, destination.path, "0"])
        return (status, destination, novo)
    }

    private func version(at app: URL) -> String? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    func testSwapReplacesTheBundleAndLeavesNothingBehind() throws {
        let result = try swap()
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(version(at: result.destination), "1.7.0")
        let left = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.contains(".novo") || $0.contains(".antigo") }
        XCTAssertEqual(left, [])
    }

    func testSwapWaitsForTheAppToLeave() throws {
        let destination = root.appendingPathComponent("Egeon Deck.app")
        let novo = root.appendingPathComponent("Egeon Deck.app.novo")
        try makeApp(at: destination, version: "1.6.0", sign: false)
        try makeApp(at: novo, version: "1.7.0", sign: false)
        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/bin/sleep")
        holder.arguments = ["1"]
        try holder.run()
        let script = root.appendingPathComponent("troca.sh")
        try UpdateSwapScript.body.write(to: script, atomically: true, encoding: .utf8)
        let swapper = Process()
        swapper.executableURL = URL(fileURLWithPath: "/bin/sh")
        swapper.arguments = [script.path, String(holder.processIdentifier), novo.path, destination.path, "0"]
        swapper.standardOutput = FileHandle.nullDevice
        try swapper.run()
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertEqual(version(at: destination), "1.6.0", "trocou com o app ainda de pé")
        holder.waitUntilExit()
        swapper.waitUntilExit()
        XCTAssertEqual(swapper.terminationStatus, 0)
        XCTAssertEqual(version(at: destination), "1.7.0")
    }
}
