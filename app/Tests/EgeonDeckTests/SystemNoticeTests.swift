import XCTest
@testable import EgeonDeck

/// O aviso do macOS: só as duas paradas, com bancada e terminal separados do
/// endereço para o clique voltar ao lugar certo.
final class SystemNoticeTests: XCTestCase {
    func testAskingCarriesWhatIsWaiting() {
        let notice = SystemNotice(address: "testes-bancada/dev", activity: .asking,
                                  detail: "rm -rf build\nls")
        XCTAssertEqual(notice?.workbench, "testes-bancada")
        XCTAssertEqual(notice?.node, "dev")
        XCTAssertEqual(notice?.title, "testes-bancada · dev")
        XCTAssertEqual(notice?.body, "precisa de você — rm -rf build ls")
        XCTAssertEqual(notice?.identifier, "egeon.testes-bancada/dev")
    }

    func testFinishedWithoutDetail() {
        XCTAssertEqual(SystemNotice(address: "deck/revisor", activity: .waiting)?.body, "terminou")
        XCTAssertEqual(SystemNotice(address: "deck/revisor", activity: .waiting, detail: "  ")?.body,
                       "terminou")
    }

    func testStatesThatComeBackAloneDoNotNotify() {
        for activity: Activity in [.working, .starting, .ready, .background, .awaiting(["dev"]), .dead] {
            XCTAssertNil(SystemNotice(address: "deck/revisor", activity: activity))
        }
        XCTAssertNil(SystemNotice(address: "sem-barra", activity: .asking))
    }

    func testLongDetailIsClipped() {
        let body = SystemNotice(address: "a/b", activity: .asking,
                                detail: String(repeating: "x", count: 500))?.body ?? ""
        XCTAssertTrue(body.hasSuffix("…"))
        XCTAssertLessThan(body.count, 220)
    }
}
