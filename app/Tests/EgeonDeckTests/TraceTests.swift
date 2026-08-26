import XCTest
@testable import EgeonDeck

/// Uma entrada da trilha da bancada: o carimbo do app em volta do texto do agente.
final class TraceEntryTests: XCTestCase {
    private let at = Date(timeIntervalSince1970: 1_787_678_363)

    private func entry(_ address: String, text: String, cli: String? = nil, model: String? = nil,
                       conversation: String? = nil) -> TraceEntry {
        TraceEntry(address: address, workbenchID: "3f9a2c1d", at: at, cli: cli, model: model,
                   conversation: conversation, text: text)
    }

    func testMarkdownStampsWhoAndWith() {
        let md = entry("deck/revisor", text: "pedido: revisar o PR — entrega: 3 apontamentos",
                       cli: "Claude Code", model: "claude-haiku-4-5",
                       conversation: "3C0C394C-E0A8-46FD").markdown
        XCTAssertTrue(md.hasPrefix("## "))
        // Só o id do nó: a bancada já é o arquivo.
        XCTAssertTrue(md.contains(" · revisor\n"))
        XCTAssertFalse(md.contains("deck/"))
        XCTAssertTrue(md.contains("Claude Code · claude-haiku-4-5 · conversa 3C0C394C\n"))
        XCTAssertTrue(md.hasSuffix("\n\npedido: revisar o PR — entrega: 3 apontamentos\n\n"))
    }

    // Nó sem perfil ou antes do primeiro turno: sem carimbo, sem linha vazia sobrando.
    func testMissingIdentityLeavesNoStampLine() {
        let md = entry("deck/x", text: "fiz").markdown
        XCTAssertEqual(md.components(separatedBy: "\n").count, 5)
        XCTAssertFalse(md.contains("conversa"))
        XCTAssertTrue(entry("deck/x", text: "  ").markdown.contains("\n—\n"))
    }

    func testTextIsTrimmedAndCapped() {
        XCTAssertEqual(TraceEntry.cap("  a\nb \n", limit: 10), "a\nb")
        let long = String(repeating: "x", count: TraceEntry.textLimit + 50)
        let capped = entry("deck/x", text: long)
        XCTAssertEqual(capped.text.count, TraceEntry.textLimit + 1)
        XCTAssertTrue(capped.text.hasSuffix("…"))
    }

    func testSplitsAddress() {
        let e = entry("deck/revisor", text: "x")
        XCTAssertEqual(e.workbench, "deck")
        XCTAssertEqual(e.node, "revisor")
    }
}

/// O arquivo da bancada: um só, na pasta do id, cabeçalho uma vez, agentes em ordem.
final class TraceLogTests: XCTestCase {
    private var root: URL!
    private var log: TraceLog!
    private let at = Date(timeIntervalSince1970: 1_787_678_363)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("workbenches-\(UUID())")
        log = TraceLog(workbenches: root)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func entry(_ address: String, id: String, text: String) -> TraceEntry {
        TraceEntry(address: address, workbenchID: id, at: at, text: text)
    }

    // A pasta é o id, não o nome: "deck" apagada e recriada é outra trilha.
    func testFolderIsTheWorkbenchID() {
        XCTAssertEqual(log.file(for: entry("deck/revisor", id: "aaaa1111", text: "x")).path,
                       root.appendingPathComponent("aaaa1111/trace.md").path)
        XCTAssertEqual(log.file(for: entry("deck/dev", id: "aaaa1111", text: "x")).path,
                       log.file(for: entry("deck/revisor", id: "aaaa1111", text: "x")).path)
        XCTAssertNotEqual(log.file(for: entry("deck/dev", id: "bbbb2222", text: "x")).path,
                          log.file(for: entry("deck/dev", id: "aaaa1111", text: "x")).path)
    }

    func testHeaderCarriesNameAndIDOnceThenAgentsInterleaveInOrder() throws {
        log.record(entry("deck/a", id: "aaaa1111", text: "um"))
        log.record(entry("deck/b", id: "aaaa1111", text: "dois"))
        log.record(entry("deck/a", id: "aaaa1111", text: "três"))
        log.flush()
        let text = try String(contentsOf: log.file(for: entry("deck/a", id: "aaaa1111", text: "")),
                              encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# deck\nbancada `aaaa1111`\n"))
        XCTAssertEqual(text.components(separatedBy: "# deck\n").count, 2)
        XCTAssertEqual(text.components(separatedBy: "\n## ").count, 4)
        let um = text.range(of: "\num\n")!, dois = text.range(of: "\ndois\n")!, tres = text.range(of: "\ntrês\n")!
        XCTAssertLessThan(um.lowerBound, dois.lowerBound)
        XCTAssertLessThan(dois.lowerBound, tres.lowerBound)
    }
}
