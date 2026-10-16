import XCTest
@testable import EgeonDeck

/// Pasta que existe mas não se lê: é o caso que o `fileExists` não vê e que
/// derrubava o agente no arranque.
final class FolderAccessTests: XCTestCase {
    func testReadableMissingAndBlocked() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder-access-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertEqual(FolderAccess.check(root), .ok)
        XCTAssertEqual(FolderAccess.check(root.appendingPathComponent("nada")), .missing)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        XCTAssertEqual(FolderAccess.check(root), .denied(folder: nil))
        XCTAssertNotNil(FolderAccess.check(root).message)
    }

    func testNamesTheProtectedFolderAsSettingsShowsIt() {
        XCTAssertEqual(FolderAccess.protectedFolder(of: "/Users/x/Documents/proj", home: "/Users/x"),
                       "Documentos")
        XCTAssertEqual(FolderAccess.protectedFolder(of: "/Users/x/Desktop", home: "/Users/x"), "Mesa")
        XCTAssertNil(FolderAccess.protectedFolder(of: "/Users/x/Documentsish/a", home: "/Users/x"))
        XCTAssertNil(FolderAccess.protectedFolder(of: "/Users/x/code", home: "/Users/x"))
        let message = FolderAccess.denied(folder: "Documentos").message ?? ""
        XCTAssertTrue(message.contains("a pasta Documentos"))
        XCTAssertNil(FolderAccess.ok.message)
    }

    // O pedido de novo zera a decisão do serviço certo, e só das três pastas.
    func testServiceOfEachProtectedFolder() {
        XCTAssertEqual(FolderAccess.service(of: "Documentos"), "SystemPolicyDocumentsFolder")
        XCTAssertEqual(FolderAccess.service(of: "Mesa"), "SystemPolicyDesktopFolder")
        XCTAssertEqual(FolderAccess.service(of: "Transferências"), "SystemPolicyDownloadsFolder")
        XCTAssertNil(FolderAccess.service(of: "Outra"))
    }

    // Fora de um .app (o `swift test`) não há o que zerar: devolve a conferência.
    func testRequestOutsideAnAppIsJustTheCheck() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folder-request-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(FolderAccess.request(root), .ok)
    }
}
