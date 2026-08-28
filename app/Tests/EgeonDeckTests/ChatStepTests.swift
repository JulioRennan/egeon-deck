import XCTest
@testable import EgeonDeck

/// O passo inteiro (ADR-039): o resultado casa com o passo pelo id, o diff vem
/// do `structuredPatch` quando chega, a saída tem teto, e o markdown mínimo da
/// bolha lê como o terminal.
final class ChatStepTests: XCTestCase {
    private func line(_ type: String, at: String, _ message: String, extra: String = "") -> String {
        #"{"type":"\#(type)","timestamp":"\#(at)","uuid":"\#(at)","message":\#(message)\#(extra)}"#
    }

    func testBashResultFillsCommandOutputAndError() throws {
        let jsonl = [
            line("user", at: "2026-08-25T17:00:00Z", #"{"content":"faz"}"#),
            line("assistant", at: "2026-08-25T17:00:01Z",
                 #"{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"swift test","description":"Roda os testes"}}]}"#),
            line("user", at: "2026-08-25T17:00:02Z",
                 #"{"content":[{"type":"tool_result","tool_use_id":"t1","content":"ok\n131 tests"}]}"#,
                 extra: #","toolUseResult":{"stdout":"ok\n131 tests","stderr":"","interrupted":false}"#),
            line("assistant", at: "2026-08-25T17:00:03Z",
                 #"{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"cd nope"}}]}"#),
            line("user", at: "2026-08-25T17:00:04Z",
                 #"{"content":[{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":"Exit code 1\nno such file"}]}"#,
                 extra: #","toolUseResult":"Error: Exit code 1\nno such file""#),
        ].joined(separator: "\n")
        let turn = try XCTUnwrap(ClaudeTranscript.parse(jsonl).first)
        XCTAssertEqual(turn.steps.count, 2)
        let first = turn.steps[0]
        XCTAssertEqual(first.text, "Roda os testes")
        XCTAssertEqual(first.detail, "swift test")
        XCTAssertEqual(first.output, "ok\n131 tests")
        XCTAssertFalse(first.isError)
        let second = turn.steps[1]
        // Sem description, o comando É a linha: não repete embaixo.
        XCTAssertEqual(second.text, "cd nope")
        XCTAssertNil(second.detail)
        XCTAssertTrue(second.isError)
        XCTAssertEqual(second.output, "Exit code 1\nno such file")
        // A cadeia carrega o mesmo passo, com o resultado.
        guard case .step(let inChain) = turn.parts[1] else { return XCTFail("parte errada") }
        XCTAssertEqual(inChain, second)
    }

    func testEditShowsDiffAtToolUseAndPatchWhenResultArrives() throws {
        let use = line("assistant", at: "2026-08-25T17:00:01Z",
            #"{"content":[{"type":"tool_use","id":"e1","name":"Edit","input":{"file_path":"/x/app/A.swift","old_string":"let a = 1","new_string":"let a = 2\nlet b = 3"}}]}"#)
        let prompt = line("user", at: "2026-08-25T17:00:00Z", #"{"content":"faz"}"#)
        let before = try XCTUnwrap(ClaudeTranscript.parse([prompt, use].joined(separator: "\n")).first)
        XCTAssertEqual(before.steps[0].glyph, "±")
        XCTAssertEqual(before.steps[0].text, "app/A.swift")
        XCTAssertEqual(before.steps[0].diff, ["-let a = 1", "+let a = 2", "+let b = 3"])

        let result = line("user", at: "2026-08-25T17:00:02Z",
            #"{"content":[{"type":"tool_result","tool_use_id":"e1","content":"The file has been updated"}]}"#,
            extra: #","toolUseResult":{"filePath":"/x/app/A.swift","structuredPatch":[{"oldStart":1,"oldLines":2,"newStart":1,"newLines":3,"lines":[" import Foundation","-let a = 1","+let a = 2","+let b = 3"]}]}"#)
        let after = try XCTUnwrap(ClaudeTranscript.parse([prompt, use, result].joined(separator: "\n")).first)
        // Com o cabeçalho do trecho: é dele que a vista lado a lado numera.
        XCTAssertEqual(after.steps[0].diff, ["@@ -1,2 +1,3 @@", " import Foundation", "-let a = 1", "+let a = 2", "+let b = 3"])
        // Edição não mostra "The file has been updated": o diff já diz.
        XCTAssertNil(after.steps[0].output)
        XCTAssertEqual(after.steps[0].diffCounts?.added, 2)
        XCTAssertEqual(after.steps[0].diffCounts?.removed, 1)
        // Recolhido, a linha do passo ainda diz o tamanho da mudança.
        XCTAssertTrue(ChatBlockLayout.render(after.steps[0], expanded: false).string.hasSuffix("+2 −1"))
        XCTAssertFalse(ChatBlockLayout.render(after.steps[0], expanded: false).string.contains("import"))
    }

    func testWriteIsAllAddedAndReadCountsLines() throws {
        let jsonl = [
            line("user", at: "2026-08-25T17:00:00Z", #"{"content":"faz"}"#),
            line("assistant", at: "2026-08-25T17:00:01Z",
                 #"{"content":[{"type":"tool_use","id":"w1","name":"Write","input":{"file_path":"/x/N.swift","content":"a\nb"}}]}"#),
            line("assistant", at: "2026-08-25T17:00:02Z",
                 #"{"content":[{"type":"tool_use","id":"r1","name":"Read","input":{"file_path":"/x/N.swift"}}]}"#),
            line("user", at: "2026-08-25T17:00:03Z",
                 #"{"content":[{"type":"tool_result","tool_use_id":"r1","content":"1\ta\n2\tb"}]}"#,
                 extra: #","toolUseResult":{"type":"text","file":{"filePath":"/x/N.swift","numLines":2,"totalLines":2}}"#),
            line("assistant", at: "2026-08-25T17:00:04Z",
                 #"{"content":[{"type":"tool_use","id":"g1","name":"Grep","input":{"pattern":"foo","path":"app/"}}]}"#),
        ].joined(separator: "\n")
        let turn = try XCTUnwrap(ClaudeTranscript.parse(jsonl).first)
        XCTAssertEqual(turn.steps[0].diff, ["+a", "+b"])
        XCTAssertEqual(turn.steps[1].output, "2 linhas")
        XCTAssertEqual(turn.steps[2].text, "Grep")
        XCTAssertEqual(turn.steps[2].detail, "path: app/\npattern: foo")
    }

    func testOutputIsCappedByLinesAndBytes() {
        let many = (1...100).map(String.init).joined(separator: "\n")
        let capped = ChatStep.capped(many)
        XCTAssertEqual(capped.split(separator: "\n").count, ChatStep.maxOutputLines + 1)
        XCTAssertTrue(capped.hasSuffix("… +60 linhas"))

        let wide = String(repeating: "x", count: 5000)
        let cut = ChatStep.capped(wide)
        XCTAssertLessThan(cut.utf8.count, 2200)
        XCTAssertTrue(cut.hasSuffix("… 5000 bytes ao todo"))
        XCTAssertEqual(ChatStep.capped("  \n"), "")
    }

    func testDiffIsCapped() {
        let big = (1...300).map { "l\($0)" }.joined(separator: "\n")
        let diff = ClaudeTranscript.diff(old: "", new: big)
        XCTAssertEqual(diff?.count, ChatStep.maxDiffLines + 1)
        XCTAssertEqual(diff?.last, "… +100 linhas")
        XCTAssertNil(ClaudeTranscript.diff(old: "", new: ""))
    }

    // O passo inteiro vai para o histórico aninhado; a forma chata antiga
    // (glyph/text soltos) ainda decodifica.
    func testStepPartRoundTripsAndOldFlatFormDecodes() throws {
        let step = ChatStep(glyph: "$", text: "Roda", toolId: "t1", detail: "swift test",
                            diff: nil, output: "ok", isError: false)
        let data = try ChatHistory.encoder.encode(ChatPart.step(step))
        XCTAssertEqual(try ChatHistory.decoder.decode(ChatPart.self, from: data), .step(step))

        let flat = #"{"kind":"step","glyph":"±","text":"a.swift"}"#
        XCTAssertEqual(try ChatHistory.decoder.decode(ChatPart.self, from: Data(flat.utf8)),
                       .step(ChatStep(glyph: "±", text: "a.swift")))
    }

    func testMarkdownBlocksAndSpans() {
        let text = """
        ## Título
        Vou **listar** os `arquivos`.

        - um
        - dois
        3. três
        ```
        let x = 1
        ```
        """
        XCTAssertEqual(MarkdownLite.blocks(text), [
            .heading(level: 2, spans: [.text("Título")]),
            .paragraph([.text("Vou "), .bold("listar"), .text(" os "), .code("arquivos"), .text(".")]),
            .bullet([.text("um")]),
            .bullet([.text("dois")]),
            .numbered([.text("3. três")]),
            .code(language: nil, text: "let x = 1"),
        ])
        // `**` dentro de crase é literal; `**` sem par também.
        XCTAssertEqual(MarkdownLite.spans("`a**b` e **solto"), [.code("a**b"), .text(" e **solto")])
        let rendered = MarkdownLite.render("**x**", font: .systemFont(ofSize: 13), color: .white)
        XCTAssertEqual(rendered.string, "x")
        let font = rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }
}
