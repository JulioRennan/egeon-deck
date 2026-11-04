import AppKit
import XCTest
@testable import EgeonDeck

final class ContextGaugeTests: XCTestCase {
    private func model(window: Int?) -> ModelCatalog.Model {
        ModelCatalog.Model(id: "claude-x", family: "x", label: "X", efforts: [], defaultEffort: nil,
                           contextWindow: window)
    }

    func testShowsTheShareInUseRoundedUp() {
        let gauge = ContextGauge(tokens: 170_500, requested: nil, model: model(window: 1_000_000))
        XCTAssertEqual(gauge?.usedPercent, 18)
        XCTAssertEqual(gauge?.text, "18%")
        XCTAssertEqual(gauge?.detail, "170K de 1M em uso")
        XCTAssertEqual(ContextGauge(tokens: 1, requested: nil, model: model(window: 1_000_000))?.text, "1%")
    }

    func testHueGoesFromGreenToRedAsTheWindowFills() {
        let hue = { (tokens: Int) in ContextGauge(tokens: tokens, requested: nil, model: self.model(window: 100_000))!.hue }
        XCTAssertEqual(hue(0), 120)
        XCTAssertEqual(hue(50_000), 60)
        XCTAssertEqual(hue(100_000), 0)
        XCTAssertGreaterThan(hue(80_000), hue(90_000))
    }

    func testIndicatorWithoutReadingShowsADash() {
        let indicator = ContextIndicator()
        XCTAssertEqual(indicator.text, "—")
        indicator.gauge = ContextGauge(tokens: 500_000, requested: nil, model: model(window: 1_000_000))
        XCTAssertEqual(indicator.text, "50%")
        XCTAssertGreaterThan(indicator.fittingSize.width, 12)
        indicator.gauge = nil
        XCTAssertEqual(indicator.text, "—")
    }

    /// `[1m]` não aparece no transcript: só o pedido diz que a janela é a grande.
    func testAskedLargeWindowWinsOverTheCatalog() {
        XCTAssertEqual(ContextGauge(tokens: 100_000, requested: "opus[1m]", model: model(window: 200_000))?.window, 1_000_000)
    }

    func testUsageAboveTheCatalogWindowMeansTheLargeOne() {
        XCTAssertEqual(ContextGauge(tokens: 300_000, requested: nil, model: model(window: 200_000))?.window, 1_000_000)
    }

    func testFullWindowStopsAtAHundred() {
        let gauge = ContextGauge(tokens: 1_200_000, requested: nil, model: model(window: 1_000_000))
        XCTAssertEqual(gauge?.usedPercent, 100)
        XCTAssertEqual(gauge?.hue, 0)
    }

    func testUnknownWindowHasNoGauge() {
        XCTAssertNil(ContextGauge(tokens: 10, requested: nil, model: model(window: nil)))
        XCTAssertNil(ContextGauge(tokens: 10, requested: nil, model: nil))
    }

    func testShortNumbers() {
        XCTAssertEqual(ContextGauge.short(900), "900")
        XCTAssertEqual(ContextGauge.short(200_000), "200K")
        XCTAssertEqual(ContextGauge.short(1_000_000), "1M")
        XCTAssertEqual(ContextGauge.short(1_500_000), "1.5M")
    }

    func testRegistryReadsTheWindowNotTheMaximum() {
        let wide = #"{id:"claude-opus-5-5",family:"opus",display_name:"Opus 5.5",context:{window:1e6,native_1m:!0},capabilities:["effort"]}"#
        let narrow = #"{id:"claude-sonnet-4-6",family:"sonnet",display_name:"Sonnet 4.6",context:{window:200000,maximum_window:1e6},capabilities:["effort"]}"#
        let late = #"{id:"claude-x",family:"x",display_name:"X",context:{native_1m:!0,window:300000},capabilities:[]}"#
        let none = #"{id:"claude-3-5-haiku",family:"haiku",display_name:"Haiku",capabilities:[]}"#
        XCTAssertEqual(ClaudeModelRegistry.parse(entry: wide)?.contextWindow, 1_000_000)
        XCTAssertEqual(ClaudeModelRegistry.parse(entry: narrow)?.contextWindow, 200_000)
        XCTAssertEqual(ClaudeModelRegistry.parse(entry: late)?.contextWindow, 300_000)
        XCTAssertNil(ClaudeModelRegistry.parse(entry: none)?.contextWindow)
    }

    /// Cache gravado antes do campo existir precisa pedir releitura.
    func testCatalogWithoutSchemaIsOld() throws {
        let old = try JSONDecoder().decode(ModelCatalog.self, from: Data(#"{"models":[]}"#.utf8))
        XCTAssertNil(old.schema)
        XCTAssertEqual(ModelCatalog(models: []).schema, ModelCatalog.currentSchema)
    }
}

final class ContextTokensTests: XCTestCase {
    private func assistant(_ input: Int, read: Int = 0, write: Int = 0, output: Int = 5, id: String = "m",
                           sidechain: Bool = false, model: String = "claude-x") -> String {
        #"{"type":"assistant","isSidechain":\#(sidechain),"message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_read_input_tokens":\#(read),"cache_creation_input_tokens":\#(write)}}}"#
    }

    func testCountsThePromptOfTheLastAnswerWithoutOutput() {
        let text = [assistant(1), assistant(10, read: 100, write: 1000)].joined(separator: "\n")
        XCTAssertEqual(ClaudeTranscript.contextTokens(in: text), 1110)
    }

    func testSkipsSubagentsAndFabricatedAnswers() {
        let text = [assistant(10), assistant(99, sidechain: true), assistant(0, model: "<synthetic>")]
            .joined(separator: "\n")
        XCTAssertEqual(ClaudeTranscript.contextTokens(in: text), 10)
    }

    func testCompactionHidesTheOldNumberUntilTheNextAnswer() {
        let boundary = #"{"type":"system","subtype":"compact_boundary"}"#
        XCTAssertNil(ClaudeTranscript.contextTokens(in: assistant(500) + "\n" + boundary))
        XCTAssertEqual(ClaudeTranscript.contextTokens(in: [assistant(500), boundary, assistant(20)].joined(separator: "\n")), 20)
    }

    /// Uma conversa que só cita o nome do marcador não foi compactada.
    func testQuotingTheBoundaryIsNotCompaction() {
        let quote = #"{"type":"user","message":{"content":"o compact_boundary é \"compact_boundary\""}}"#
        XCTAssertEqual(ClaudeTranscript.contextTokens(in: assistant(500) + "\n" + quote), 500)
    }

    func testNoAnswerYet() {
        XCTAssertNil(ClaudeTranscript.contextTokens(in: #"{"type":"user","message":{"content":"oi"}}"#))
    }
}
