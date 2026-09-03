import XCTest
@testable import EgeonDeck

/// A skill que o app publica para o Claude Code. Ela existe para competir com a
/// ferramenta de subagente do próprio CLI na hora em que o usuário fala em outro
/// agente — então o que este teste guarda é justamente o que faz essa disputa:
/// o frontmatter na primeira linha, os gatilhos em português e a regra de olhar
/// os vizinhos antes de abrir um subagente (ADR-054).
final class ClaudeSkillTests: XCTestCase {
    /// O frontmatter, sem os `---`. Vazio se o arquivo não abrir com um.
    private func frontmatter(of body: String) -> String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "---", let close = lines.dropFirst().firstIndex(of: "---")
        else { return "" }
        return lines[1..<close].joined(separator: "\n")
    }

    func testFrontmatterIsReadableByTheCLI() {
        // O CLI só lê o frontmatter quando o `---` é a PRIMEIRA linha; senão o
        // arquivo inteiro vira conteúdo e a skill nunca dispara sozinha.
        let front = frontmatter(of: ClaudeSkill.body)
        XCTAssertFalse(front.isEmpty, "o frontmatter tem de abrir o arquivo")
        XCTAssertTrue(front.contains("name: egeon"))
        XCTAssertTrue(front.contains("description:"))
        XCTAssertTrue(front.contains("when_to_use:"), "os gatilhos moram aqui")
        XCTAssertTrue(front.contains("user-invocable: false"),
                      "não é comando que se digita: é o que o agente precisa saber")
    }

    /// As frases que hoje levam ao subagente têm de estar no frontmatter — é por
    /// ele que o CLI decide carregar a skill, não pelo corpo.
    func testTriggerPhrasesAreInTheFrontmatter() {
        let front = frontmatter(of: ClaudeSkill.body)
        for phrase in ["pede pro", "delega isso", "monta um time", "em paralelo",
                       "usa outro agente"] {
            XCTAssertTrue(front.contains(phrase), "falta o gatilho '\(phrase)'")
        }
    }

    func testBodyTeachesPeersBeforeSubagent() {
        let body = ClaudeSkill.body
        for command in ["egeon peers", "egeon peek", "egeon send", "egeon status"] {
            XCTAssertTrue(body.contains(command), "o corpo tem de ensinar `\(command)`")
        }
        // A regra que resolve o problema: subagente do CLI não é resposta a
        // "pede pro fulano".
        XCTAssertTrue(body.contains("Task/Agent"),
                      "o corpo nomeia a ferramenta que ele não deve usar ali")
        XCTAssertTrue(body.contains("aresta"),
                      "lista vazia é aresta que falta, não motivo para inventar substituto")
    }

    /// Publicada numa pasta NOSSA, por flavor, e não no `~/.claude` do usuário.
    func testSkillLivesUnderTheFolderHandedToTheCLI() {
        let path = ClaudeSkill.skillFile.path
        XCTAssertTrue(path.hasSuffix("/.claude/skills/egeon/SKILL.md"),
                      "o CLI procura exatamente neste caminho dentro da pasta apontada")
        XCTAssertTrue(path.hasPrefix(ClaudeSkill.directory.path + "/"),
                      "tudo o que o `--add-dir` entrega mora sob a pasta apontada")
        XCTAssertTrue(ClaudeSkill.directory.path.hasPrefix(Flavor.current.configDirectory.path),
                      "por flavor: o dev não reescreve o que o estável está lendo")
    }

    func testInstallWritesTheSkillFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }

        let file = try XCTUnwrap(ClaudeSkill.install(into: root))
        XCTAssertEqual(file, ClaudeSkill.skillFile(in: root))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), ClaudeSkill.body)

        // Reescrita a cada arranque: o texto acompanha a versão que subiu.
        try "velho".write(to: file, atomically: true, encoding: .utf8)
        ClaudeSkill.install(into: root)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), ClaudeSkill.body)
    }
}
