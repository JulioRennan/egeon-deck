import XCTest
@testable import EgeonDeck

/// Linguagem pela extensão, e o tokenizador por linha.
final class SyntaxLiteTests: XCTestCase {
    func testLanguageComesFromExtensionOnly() {
        XCTAssertEqual(Language.detect(path: "app/main.py"), .python)
        XCTAssertEqual(Language.detect(path: "lib/widgets/home.dart"), .dart)
        XCTAssertEqual(Language.detect(path: "src/App.tsx"), .typescript)
        XCTAssertEqual(Language.detect(path: "index.HTML"), .html)
        XCTAssertEqual(Language.detect(path: "config.json"), .json)
        XCTAssertEqual(Language.detect(path: "Sources/EgeonDeck/ChatBlock.swift"), .swift)
        XCTAssertEqual(Language.detect(path: "app/dev.sh"), .shell)
        XCTAssertEqual(Language.detect(path: "Makefile"), .plain)
        XCTAssertEqual(Language.detect(path: ".env"), .plain)
    }

    func testLanguageFromFenceLabelAndFromCommand() {
        XCTAssertEqual(Language.named("python"), .python)
        XCTAssertEqual(Language.named("TS"), .typescript)
        XCTAssertEqual(Language.named("swift"), .swift)
        XCTAssertEqual(Language.named("bash"), .shell)
        XCTAssertEqual(Language.named("cobol"), .plain)
        XCTAssertEqual(Language.detect(inCommand: "cat app/build/x/config.json"), .json)
        XCTAssertEqual(Language.detect(inCommand: "head -20 'lib/main.dart' | grep x"), .dart)
        XCTAssertEqual(Language.detect(inCommand: "ls -la"), .plain)
        // O passo de leitura: a linguagem sai do arquivo citado no título.
        XCTAssertEqual(Language.detect(inCommand: "read Chat/Models/ChatBlock.swift"), .swift)
        XCTAssertEqual(Language.detect(inCommand: "git log --oneline -2"), .plain)
    }

    func testSwiftAndShellTokens() {
        let swift = SyntaxLite.tokens("private let name = \"oi\"  // nota", language: .swift)
        XCTAssertEqual(swift.filter { $0.kind == .keyword }.map(\.text), ["private", "let"])
        XCTAssertEqual(swift.filter { $0.kind == .string }.map(\.text), ["\"oi\""])
        XCTAssertEqual(swift.filter { $0.kind == .comment }.map(\.text), ["// nota"])

        let shell = SyntaxLite.tokens("for f in *.swift; do echo 1; done  # laço", language: .shell)
        XCTAssertEqual(shell.filter { $0.kind == .keyword }.map(\.text), ["for", "in", "do", "echo", "done"])
        XCTAssertEqual(shell.filter { $0.kind == .comment }.map(\.text), ["# laço"])
    }

    func testFencedBlockKeepsItsLabel() {
        XCTAssertEqual(MarkdownLite.blocks("```python\nx = 1\n```"),
                       [.code(language: "python", text: "x = 1")])
    }

    func testPython() {
        let tokens = SyntaxLite.tokens("def load(path: str) -> None:  # abre", language: .python)
        XCTAssertEqual(tokens.first, Token(kind: .keyword, text: "def"))
        XCTAssertTrue(tokens.contains(Token(kind: .keyword, text: "None")))
        XCTAssertEqual(tokens.last, Token(kind: .comment, text: "# abre"))
        XCTAssertEqual(SyntaxLite.tokens("x = \"a # não é comentário\"", language: .python)
                        .filter { $0.kind == .comment }, [])
    }

    func testTypeScriptAndDart() {
        let ts = SyntaxLite.tokens("const total: number = items.length + 2; // soma", language: .typescript)
        XCTAssertEqual(ts.first, Token(kind: .keyword, text: "const"))
        XCTAssertTrue(ts.contains(Token(kind: .number, text: "2")))
        XCTAssertEqual(ts.last, Token(kind: .comment, text: "// soma"))
        XCTAssertTrue(SyntaxLite.tokens("const s = `tpl ${x}`;", language: .typescript)
                        .contains(Token(kind: .string, text: "`tpl ${x}`")))
        let dart = SyntaxLite.tokens("final Widget child = Text('oi');", language: .dart)
        XCTAssertEqual(dart[0], Token(kind: .keyword, text: "final"))
        XCTAssertTrue(dart.contains(Token(kind: .type, text: "Text")))
        XCTAssertTrue(dart.contains(Token(kind: .string, text: "'oi'")))
    }

    func testHTML() {
        let tokens = SyntaxLite.tokens("<a href=\"/x\" class='b'>Oi</a><!-- c -->", language: .html)
        XCTAssertEqual(tokens[0], Token(kind: .tag, text: "<a"))
        XCTAssertTrue(tokens.contains(Token(kind: .attribute, text: "href")))
        XCTAssertTrue(tokens.contains(Token(kind: .string, text: "\"/x\"")))
        XCTAssertTrue(tokens.contains(Token(kind: .plain, text: "Oi")))
        XCTAssertTrue(tokens.contains(Token(kind: .tag, text: "</a>")))
        XCTAssertEqual(tokens.last, Token(kind: .comment, text: "<!-- c -->"))
    }

    func testJSONAndPlain() {
        let json = SyntaxLite.tokens("  \"debug\": true, \"port\": 8392,", language: .json)
        XCTAssertTrue(json.contains(Token(kind: .string, text: "\"debug\"")))
        XCTAssertTrue(json.contains(Token(kind: .keyword, text: "true")))
        XCTAssertTrue(json.contains(Token(kind: .number, text: "8392")))
        XCTAssertEqual(SyntaxLite.tokens("qualquer coisa", language: .plain),
                       [Token(kind: .plain, text: "qualquer coisa")])
        // Identificador com dígito não é número: `x2` fica inteiro.
        XCTAssertEqual(SyntaxLite.tokens("x2 = 3", language: .python),
                       [Token(kind: .plain, text: "x2 = "), Token(kind: .number, text: "3")])
    }
}
