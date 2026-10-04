import XCTest
@testable import EgeonDeck

/// `egeon peek` — ler a tela de outro terminal. De fora (você, pelo socket) vale
/// para qualquer alvo; de dentro de um terminal, só para quem ele já pode
/// acionar: espiar um nó sem aresta seria olhar fora da topologia que o canvas
/// desenha (ADR-054).
final class PeekGuardTests: XCTestCase {
    func testYouMayPeekAnyone() {
        // Origem nil é você: `curl` no socket, a extensão, um teste.
        XCTAssertTrue(Dispatcher.mayPeek("deck/back", from: nil, peers: []))
    }

    func testAgentMayPeekOnlyItsPeers() {
        let peers = ["deck/revisor", "deck/back"]
        XCTAssertTrue(Dispatcher.mayPeek("deck/revisor", from: "deck/front", peers: peers))
        XCTAssertFalse(Dispatcher.mayPeek("outra/qualquer", from: "deck/front", peers: peers),
                       "sem aresta, não há o que espiar")
    }

    func testAgentMayAlwaysPeekItself() {
        XCTAssertTrue(Dispatcher.mayPeek("deck/front", from: "deck/front", peers: []))
    }
}

/// O script `egeon` é gerado pelo app: o que ele oferece é contrato com o
/// agente, e a ajuda impressa é recortada do próprio cabeçalho por número de
/// linha — comando novo sem ajustar o corte deixa a ajuda cortada pela metade.
final class EgeonCLIBodyTests: XCTestCase {
    func testPeekIsOfferedAndDocumented() throws {
        let body = EgeonCLI.body
        // A indentação do literal multilinha some: o `case` fica com 2 espaços.
        XCTAssertTrue(body.contains("\n  peek)"), "o subcomando existe")
        XCTAssertTrue(body.contains("/peek?target="))

        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        // A ajuda é `sed -n '<a>,<b>p'` sobre o próprio arquivo, 1-based.
        let usage = try XCTUnwrap(lines.first(where: { $0.contains("sed -n '") }).map(String.init))
        let range = usage.split(separator: "'")[1].dropLast()  // "2,10p" → "2,10"
        let bounds = range.split(separator: ",").compactMap { Int($0) }
        XCTAssertEqual(bounds.count, 2)
        let shown = lines[(bounds[0] - 1)..<bounds[1]].joined(separator: "\n")
        for command in ["egeon peers", "egeon send", "egeon peek", "egeon trace", "egeon status",
                        "egeon bench", "egeon models", "egeon plan", "egeon apply", "egeon guide"] {
            XCTAssertTrue(shown.contains(command), "a ajuda impressa não mostra `\(command)`")
        }
    }

    /// Os comandos do maestro existem e vão às rotas certas; o `guide` imprime
    /// o manual inteiro, sem expandir nada dele no shell (ADR-066).
    func testMaestroCommandsAndGuide() throws {
        let body = EgeonCLI.body
        for (command, route) in [("bench", "GET /maestro/bench"), ("models", "GET /maestro/models"),
                                 ("plan", "POST \"/maestro/apply?dry=1\""),
                                 ("apply", "POST /maestro/apply")] {
            XCTAssertTrue(body.contains("\n  \(command))"), "falta o subcomando \(command)")
            XCTAssertTrue(body.contains(route), "\(command) não vai a \(route)")
        }

        let script = FileManager.default.temporaryDirectory.appendingPathComponent("egeon-\(UUID())")
        defer { try? FileManager.default.removeItem(at: script) }
        try body.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, "guide"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(output, MaestroGuide.text + "\n", "o heredoc tem de devolver o texto literal")
    }
}
