import XCTest
@testable import EgeonDeck

/// Digitar no composer não pode custar um layout da thread inteira: o pai só
/// é avisado quando a altura da caixa muda de fato, e a thread só se remede
/// quando a largura ou o conteúdo mudam.
@MainActor
final class ChatComposerTests: XCTestCase {
    func testHeightChangeFiresOnlyWhenHeightChanges() {
        let composer = ChatComposer(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        // A primeira edição anuncia a altura inicial; o que se mede é dali em diante.
        composer.text = "o"
        let baseline = composer.desiredHeight
        var calls = 0
        composer.onHeightChange = { calls += 1 }

        composer.text = "oi"
        composer.text = "oi tudo"
        composer.text = "oi tudo bem"
        XCTAssertEqual(composer.desiredHeight, baseline)
        XCTAssertEqual(calls, 0, "mesma altura, nenhum aviso ao pai")

        composer.text = "oi\ntudo\nbem"
        XCTAssertGreaterThan(composer.desiredHeight, baseline)
        XCTAssertEqual(calls, 1, "só a quebra de linha avisa")

        composer.text = ""
        XCTAssertEqual(calls, 2, "voltar ao mínimo avisa de novo")
    }

    func testTypingDoesNotRemeasureThread() {
        let container = ChatContainer(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        settle()
        let builds = container.threadBuilds
        XCTAssertGreaterThan(builds, 0, "a primeira largura monta")

        _ = container.compose("uma linha", send: false)
        _ = container.compose("duas\nlinhas", send: false)
        _ = container.compose("três\nlinhas\naqui", send: false)
        settle()
        XCTAssertEqual(container.threadBuilds, builds, "o composer crescer não remonta a thread")

        container.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        container.layoutSubtreeIfNeeded()
        settle()
        XCTAssertEqual(container.threadBuilds, builds + 1, "largura nova remede")
    }
}
