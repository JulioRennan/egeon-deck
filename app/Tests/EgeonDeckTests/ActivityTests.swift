import XCTest
@testable import EgeonDeck

/// O vocabulário de aviso (ADR-024): só a pergunta interrompe, e a cor — não o
/// glifo — é quem separa "terminou" de "precisa de você".
final class ActivityTests: XCTestCase {
    func testOnlyAskingInterrupts() {
        XCTAssertTrue(Activity.asking.needsAttention)
        for state: Activity in [.starting, .ready, .working, .waiting, .dead] {
            XCTAssertFalse(state.needsAttention, "\(state) não pode interromper")
        }
    }

    func testColorSeparatesTheTwoStops() {
        XCTAssertEqual(Activity.waiting.color, .systemGreen)
        XCTAssertEqual(Activity.asking.color, .systemOrange)
        XCTAssertEqual(Activity.dead.color, .systemRed)
        XCTAssertNil(Activity.working.color)
    }

    // `ready` não ocupa a linha do cabeçalho; os dois estados parados usam a
    // mesma bolinha.
    func testLabels() {
        XCTAssertNil(Activity.ready.label)
        XCTAssertEqual(Activity.waiting.label, "● terminou")
        XCTAssertEqual(Activity.asking.label, "● precisa de você")
    }

    // Spinner fica sem teste: a propriedade dele — girar em fase pelo relógio
    // compartilhado — só se testa injetando o relógio, e hoje ele lê Date()
    // direto. Anotado na NOTAS-PARA-REVISAO.md.
}
