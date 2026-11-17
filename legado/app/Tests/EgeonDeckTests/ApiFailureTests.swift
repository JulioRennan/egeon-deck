import XCTest
@testable import EgeonDeck

/// O que fazer com o turno que morreu por erro de API: passageiro tenta de
/// novo, limite de uso espera mais, o resto para e chama em vermelho.
final class ApiFailureTests: XCTestCase {
    func testKinds() {
        XCTAssertEqual(ApiFailure(error: "overloaded").kind, .transient)
        XCTAssertEqual(ApiFailure(error: "server_error").kind, .transient)
        XCTAssertEqual(ApiFailure(error: "unknown").kind, .transient)
        XCTAssertEqual(ApiFailure(error: "rate_limit").kind, .rateLimit)
        for fatal in ["authentication_failed", "billing_error", "invalid_request", "model_not_found", "novo_erro"] {
            XCTAssertEqual(ApiFailure(error: fatal).kind, .fatal, fatal)
        }
    }

    func testScheduleAndGivingUp() {
        let busy = ApiFailure(error: "overloaded")
        XCTAssertEqual((1...3).map { busy.delay(attempt: $0) }, [30, 120, 300])
        XCTAssertNil(busy.delay(attempt: 4))
        XCTAssertEqual(ApiFailure(error: "rate_limit").delay(attempt: 1), 120)
        XCTAssertNil(ApiFailure(error: "billing_error").delay(attempt: 1))
    }

    func testReadFromQueryAndWording() {
        let failure = ApiFailure(query: ["error": "overloaded", "detail": "Overloaded"])
        XCTAssertEqual(failure, ApiFailure(error: "overloaded", detail: "Overloaded"))
        XCTAssertNil(ApiFailure(query: [:]))
        XCTAssertTrue(failure?.retryPrompt.contains("API sobrecarregada") == true)
    }

    // Falhou chama como a pergunta: borda, som, notificação — e conta como
    // atenção na barra; a tentativa agendada conta como fundo, sem som.
    func testStatesInTheRestOfTheApp() {
        XCTAssertTrue(Activity.failed("x").needsAttention)
        XCTAssertFalse(Activity.retrying(attempt: 1, at: Date()).needsAttention)
        XCTAssertEqual(Activity.failed("x").color, .systemRed)
        XCTAssertEqual(SystemNotice(address: "deck/dev", activity: .failed("API sobrecarregada"))?.title,
                       "A bancada deck parou por um erro")
        XCTAssertEqual(SystemNotice(address: "deck/dev", activity: .failed("API sobrecarregada"))?.body,
                       "dev: API sobrecarregada")
        XCTAssertNil(SystemNotice(address: "deck/dev", activity: .retrying(attempt: 1, at: Date())))
    }
}
