import XCTest
@testable import EgeonDeck

/// O catálogo lido do binário do Claude Code: o formato é o da tabela
/// minificada da 2.1.285, recortado.
final class ModelCatalogTests: XCTestCase {
    private static let opus55 = #"{id:"claude-opus-5-5",family:"opus",display_name:"Opus 5.5",knowledge_cutoff:"June 2026",provider_ids:{first_party:"claude-opus-5-5"},capabilities:["effort","max_effort","xhigh_effort","adaptive_thinking"],default_effort:"medium",advisor_rank:4},"#
    private static let opus46 = #"{id:"claude-opus-4-6",family:"opus",display_name:"Opus 4.6",capabilities:["effort","max_effort","adaptive_thinking"],advisor_rank:4},"#
    private static let haiku = #"{id:"claude-haiku-4-5",family:"haiku",display_name:"Haiku 4.5",capabilities:["context_management"],advisor_rank:1},"#
    private static let fable = #"{id:"claude-fable-5-1",family:"fable",display_name:"Fable 5.1",capabilities:["effort","max_effort","xhigh_effort"],default_effort:"high"},"#
    /// O mesmo começo aparece em outras tabelas do CLI, sem `family`.
    private static let decoy = #"{id:"claude-opus-5-5",pricing:"tier_4_20"},"#

    private func catalog() -> ModelCatalog {
        let blob = "lixo" + Self.decoy + Self.opus55 + Self.opus46 + Self.haiku + Self.fable + Self.opus55
        return ModelCatalog(models: ClaudeModelRegistry.parse(binary: Data(blob.utf8)))
    }

    func testReadsTheTableAndSkipsDecoysAndRepeats() {
        XCTAssertEqual(catalog().models.map(\.id),
                       ["claude-opus-5-5", "claude-opus-4-6", "claude-haiku-4-5", "claude-fable-5-1"])
    }

    /// `xhigh` e `max` são capacidades à parte; sem `effort`, nenhum nível.
    func testEffortLevelsFollowCapabilities() {
        let models = Dictionary(uniqueKeysWithValues: catalog().models.map { ($0.id, $0) })
        XCTAssertEqual(models["claude-opus-5-5"]?.efforts, ["low", "medium", "high", "xhigh", "max"])
        XCTAssertEqual(models["claude-opus-5-5"]?.defaultEffort, "medium")
        XCTAssertEqual(models["claude-opus-4-6"]?.efforts, ["low", "medium", "high", "max"])
        XCTAssertEqual(models["claude-haiku-4-5"]?.efforts, [])
        XCTAssertNil(models["claude-haiku-4-5"]?.defaultEffort)
        XCTAssertEqual(models["claude-opus-5-5"]?.label, "Opus 5.5")
    }

    func testFeaturedIsTheNewestOfEachFamilyInMenuOrder() {
        XCTAssertEqual(catalog().featured.map(\.label), ["Fable 5.1", "Opus 5.5", "Haiku 4.5"])
        XCTAssertEqual(catalog().older.map(\.label), ["Opus 4.6"])
    }

    /// Id exato, id com snapshot ou `[1m]`, e apelido de família.
    func testResolvesWhatTheNodeAskedOrTheTranscriptRecorded() {
        let catalog = catalog()
        XCTAssertEqual(catalog.model(for: "claude-opus-4-6")?.label, "Opus 4.6")
        XCTAssertEqual(catalog.model(for: "claude-haiku-4-5-20251001")?.label, "Haiku 4.5")
        XCTAssertEqual(catalog.model(for: "claude-opus-5-5[1m]")?.label, "Opus 5.5")
        XCTAssertEqual(catalog.model(for: "opus")?.label, "Opus 5.5")
        XCTAssertEqual(catalog.model(for: "opusplan")?.label, "Opus 5.5")
        XCTAssertNil(catalog.model(for: "gpt-5"))
        XCTAssertNil(catalog.model(for: nil))
    }

    func testBinaryWithoutTableGivesNothing() {
        XCTAssertTrue(ClaudeModelRegistry.parse(binary: Data("sem tabela".utf8)).isEmpty)
    }

    /// Ultracode ocupa a flag do esforço; o nível segue pela variável.
    func testUltracodeMovesTheLevelToTheEnvironment() {
        let profile = AgentProfile.claudeCode
        let plain = profile.effortLaunch(effort: "high", ultracode: false)
        XCTAssertEqual(plain.arguments, ["--effort", "high"])
        XCTAssertEqual(plain.environment, [:])

        let ultra = profile.effortLaunch(effort: "high", ultracode: true)
        XCTAssertEqual(ultra.arguments, ["--effort", "ultracode"])
        XCTAssertEqual(ultra.environment, ["CLAUDE_CODE_EFFORT_LEVEL": "high"])

        XCTAssertEqual(profile.effortLaunch(effort: nil, ultracode: true).environment, [:],
                       "auto: nenhum nível forçado")
    }
}

/// A faixa do cabeçalho só aparece quando há o que escolher.
final class ModelChoiceOfferTests: XCTestCase {
    func testFlagWithEmptyListOffersNothing() throws {
        let codex = try JSONDecoder().decode(AgentProfile.self, from: Data(
            #"{"displayName":"Codex","command":["codex"],"model":["--model","{model}"],"models":[]}"#.utf8))
        XCTAssertFalse(codex.offersModelChoice(catalog: nil))
        XCTAssertTrue(codex.offersModelChoice(catalog: nil, current: "gpt-5"), "modelo à mão aparece")
        XCTAssertTrue(AgentProfile.claudeCode.offersModelChoice(catalog: nil))
    }
}
