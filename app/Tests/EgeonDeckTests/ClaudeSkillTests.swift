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

    /// O texto é português com travessão, aspas e dois-pontos no meio das frases
    /// — e um `: ` solto num escalar YAML derruba o frontmatter INTEIRO, sem
    /// erro visível: o CLI passa a usar o primeiro parágrafo do corpo como
    /// descrição, e os gatilhos somem. Aconteceu; por isso todo valor de texto
    /// vai em bloco (`>-`), onde nada disso é sintaxe.
    func testTextValuesUseBlockScalarsSoPunctuationCannotBreakTheYAML() {
        let front = frontmatter(of: ClaudeSkill.body)
        XCTAssertTrue(front.contains("description: >-"), "descrição em bloco")
        XCTAssertTrue(front.contains("when_to_use: >-"), "gatilhos em bloco")

        for line in front.split(separator: "\n") where !line.hasPrefix(" ") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, value != ">-", value != ">", value != "|" else { continue }
            // Escalar numa linha só: tem de ser simples o bastante para não
            // precisar de aspas.
            XCTAssertFalse(value.contains(": "), "`\(line)` quebra o YAML")
            XCTAssertFalse(value.contains(" #"), "`\(line)` vira comentário no meio")
        }
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

    /// No ROOT do base path, que é onde o CLI procura skill pessoal.
    func testSkillLivesAtTheRootOfEachConfig() {
        let path = ClaudeSkill.skillFile(in: URL(fileURLWithPath: "/tmp/.claude-agro")).path
        XCTAssertEqual(path, "/tmp/.claude-agro/skills/egeon/SKILL.md")
    }

    /// Uma máquina tem mais de uma configuração — `~/.claude` e `~/.claude-agro`
    /// convivem, e cada nó escolhe a sua. A skill vai em TODAS: escrever numa só
    /// deixa sem ela justamente o agente que aponta para a outra.
    func testInstallWritesIntoEveryConfig() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let configs = [root.appendingPathComponent(".claude"),
                       root.appendingPathComponent(".claude-agro")]

        let written = ClaudeSkill.install(into: configs)
        XCTAssertEqual(written, configs.map(ClaudeSkill.skillFile(in:)))
        for file in written {
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), ClaudeSkill.body)
        }

        // Reescrita a cada arranque: o texto acompanha a versão que subiu, e o
        // arquivo avisa quem manda nele.
        try "velho".write(to: written[0], atomically: true, encoding: .utf8)
        ClaudeSkill.install(into: configs)
        XCTAssertEqual(try String(contentsOf: written[0], encoding: .utf8), ClaudeSkill.body)
        XCTAssertTrue(ClaudeSkill.body.contains("Escrito pelo Egeon Deck"),
                      "o arquivo mora na config do usuário: tem de dizer que é gerado")
    }

    /// As configurações vêm do mesmo `configGlob` que o formulário do nó oferece,
    /// mais a do ambiente — que pode estar fora do padrão `~/.claude*`.
    func testConfigDirectoriesIncludeTheEnvironmentOne() throws {
        let profile = AgentProfile.claudeCode
        XCTAssertEqual(profile.configEnv, "CLAUDE_CONFIG_DIR")
        XCTAssertEqual(profile.configGlob, "~/.claude*")

        let found = ClaudeSkill.configDirectories()
        XCTAssertEqual(Set(found.map(\.standardizedFileURL)).count, found.count,
                       "sem repetir: o do ambiente costuma já estar no glob")
        if let named = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !named.isEmpty {
            let url = URL(fileURLWithPath: (named as NSString).expandingTildeInPath)
            XCTAssertTrue(found.contains { $0.standardizedFileURL == url.standardizedFileURL })
        }
    }
}
