import AppKit
import XCTest
@testable import EgeonDeck

/// O ambiente dos processos filhos: PATH enriquecido, aspas de shell e a
/// limpeza das variáveis que fariam o agente se julgar filho de outro.
final class AppEnvironmentTests: XCTestCase {
    func testEnrichedPathKeepsCurrentAndDoesNotDuplicate() {
        let enriched = AppEnvironment.enrichedPath("/usr/bin:/bin")
        let parts = enriched.split(separator: ":").map(String.init)

        XCTAssertTrue(parts.contains("/usr/bin"))
        XCTAssertTrue(parts.contains("/bin"))
        XCTAssertEqual(parts.count, Set(parts).count, "PATH com diretório repetido")

        // Idempotente: enriquecer o já enriquecido não muda nada.
        XCTAssertEqual(AppEnvironment.enrichedPath(enriched), enriched)
    }

    func testEnrichedPathOnlyAddsDirectoriesThatExist() {
        for part in AppEnvironment.enrichedPath(nil).split(separator: ":") {
            XCTAssertTrue(FileManager.default.fileExists(atPath: String(part)),
                          "\(part) entrou no PATH sem existir")
        }
    }

    // O comando é montado como string para zsh -lc: papel com aspas, $ ou ;
    // não pode virar execução.
    func testShellQuoteNeutralizesMetacharacters() {
        XCTAssertEqual(AppEnvironment.shellQuote("simples"), "'simples'")
        XCTAssertEqual(AppEnvironment.shellQuote("com espaço $HOME; rm"),
                       "'com espaço $HOME; rm'")
        XCTAssertEqual(AppEnvironment.shellQuote("o'brien"), #"'o'\''brien'"#)
    }

    // Herdadas, as CLAUDE_CODE* fazem o agente se julgar bancada filha de outra.
    func testChildEnvironmentDropsClaudeCodeVariables() {
        setenv("CLAUDE_CODE_TESTE", "x", 1)
        setenv("CLAUDECODE", "1", 1)
        defer { unsetenv("CLAUDE_CODE_TESTE"); unsetenv("CLAUDECODE") }

        let env = AppEnvironment.forChildProcess()
        XCTAssertNil(env["CLAUDE_CODE_TESTE"])
        XCTAssertNil(env["CLAUDECODE"])
        // O egeon do flavor na frente de tudo: homônimo em /usr/local/bin não
        // pode falar com o socket errado.
        XCTAssertTrue(env["PATH"]!.hasPrefix(EgeonCLI.directory.path + ":"))
    }
}

/// O arrasto para o terminal, na parte que dá para exercitar sem tela: um
/// NSPasteboard próprio com URLs de arquivo.
final class TerminalDropTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() {
        pasteboard = NSPasteboard(name: NSPasteboard.Name("egeon-teste-drop"))
        pasteboard.clearContents()
    }

    override func tearDown() { pasteboard.releaseGlobally() }

    func testFileDropBecomesQuotedPathsWithTrailingSpace() throws {
        let a = URL(fileURLWithPath: "/tmp/um arquivo.pdf")
        let b = URL(fileURLWithPath: "/tmp/outro.swift")
        pasteboard.writeObjects([a as NSURL, b as NSURL])

        let text = try XCTUnwrap(TerminalDrop.text(from: pasteboard))
        // Aspas só onde o caminho precisa (espaço quebraria o comando); espaço
        // no fim porque o cursor fica pronto para a frase que acompanha o arquivo.
        XCTAssertEqual(text, "'/tmp/um arquivo.pdf' /tmp/outro.swift ")
    }

    func testEmptyPasteboardIsNothing() {
        XCTAssertNil(TerminalDrop.text(from: pasteboard))
        XCTAssertFalse(TerminalDrop.accepts(pasteboard))
    }

    func testAcceptsFileURLs() {
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/x") as NSURL])
        XCTAssertTrue(TerminalDrop.accepts(pasteboard))
    }
}
