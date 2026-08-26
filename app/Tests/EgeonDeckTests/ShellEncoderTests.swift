import XCTest
@testable import EgeonDeck

/// O `enc()` que vai nos scripts gerados, executado de verdade pelo bash:
/// bancada com espaço e `+` no nome ("SPEI + SPI") quebrava a linha HTTP do
/// gancho, e o alvo chegava como "SPEI".
final class ShellEncoderTests: XCTestCase {
    private func enc(_ value: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Pelo stdin, não por argv: o Foundation decompõe o UTF-8 (NFD) ao
        // montar os argumentos, e "ção" chegaria como outra sequência de bytes.
        process.arguments = ["-c", ControlSocket.shellEncoder + "\nenc \"$(cat)\""]
        let input = Pipe()
        process.standardInput = input
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        input.fileHandleForWriting.write(Data(value.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    func testEncodesSpacePlusAndUTF8ByteByByte() throws {
        XCTAssertEqual(try enc("SPEI + SPI/backend"), "SPEI%20%2B%20SPI/backend")
        XCTAssertEqual(try enc("deck/revisor"), "deck/revisor")
        XCTAssertEqual(try enc("ação/x"), "a%C3%A7%C3%A3o/x")
        XCTAssertEqual(try enc("a&b=c?d"), "a%26b%3Dc%3Fd")
    }
}
