import XCTest
@testable import EgeonDeck

/// O plano do maestro (ADR-066): o que o JSON diz, o que o planejador aceita,
/// e a bancada que sai dele. Quem escreve o plano é um modelo — o que estes
/// testes guardam é que erro dele vira mensagem clara e nunca meia bancada.
final class MaestroPlanTests: XCTestCase {
    private func parse(_ json: String) -> Result<MaestroPlan, MaestroPlan.ParseError> {
        MaestroPlan.parse(Data(json.utf8))
    }

    private let catalog = ModelCatalog(models: [
        .init(id: "claude-opus-5-5", family: "opus", label: "Opus 5.5",
              efforts: ["low", "medium", "high", "xhigh", "max"], defaultEffort: "high"),
        .init(id: "claude-sonnet-5-5", family: "sonnet", label: "Sonnet 5.5",
              efforts: ["low", "medium", "high"], defaultEffort: "medium"),
        .init(id: "claude-haiku-4-5", family: "haiku", label: "Haiku 4.5",
              efforts: [], defaultEffort: nil),
    ])

    private func context(busy: Set<String> = [], background: Set<String> = [],
                         missing: Set<String> = []) -> MaestroContext {
        var context = MaestroContext(caller: "maestro",
                                     profiles: ["claude": .claudeCode,
                                                "opencode": AgentProfile(displayName: "OpenCode",
                                                                         command: ["opencode"])])
        let catalog = self.catalog
        context.catalog = { $0.command.first == "claude" ? catalog : nil }
        context.working = busy
        context.background = background
        context.directoryExists = { path in !missing.contains(where: { path.hasSuffix($0) }) }
        context.suggestedConfig = { $0 == "claude" ? "~/.claude-agro" : nil }
        context.knownConfigs = { _ in ["~/.claude", "~/.claude-agro"] }
        return context
    }

    private func bench() -> WorkbenchConfig {
        var maestro = NodeConfig(type: .agent, id: "maestro")
        maestro.agent = "claude"
        maestro.maestro = true
        var revisor = NodeConfig(type: .agent, id: "revisor")
        revisor.agent = "claude"
        revisor.model = "sonnet"
        revisor.prompt = "Revise."
        revisor.conversationId = "conv-revisor"
        revisor.conversationStarted = true
        let shell = NodeConfig(type: .shell, id: "sh")
        return WorkbenchConfig(name: "deck", path: "/tmp/deck", nodes: [maestro, revisor, shell],
                               edges: [EdgeConfig(from: "maestro", to: "revisor"),
                                       EdgeConfig(from: "revisor", to: "maestro")])
    }

    private func plan(_ json: String, busy: Set<String> = [], background: Set<String> = [],
                      missing: Set<String> = []) -> MaestroOutcome {
        guard case .success(let plan) = parse(json) else {
            XCTFail("plano não leu: \(json)")
            return MaestroOutcome(next: bench())
        }
        return MaestroPlanner.plan(plan, on: bench(), context: context(busy: busy, background: background,
                                                                  missing: missing))
    }

    // MARK: - Leitura

    func testAbsentNullAndValueAreThreeDifferentThings() throws {
        guard case .success(let plan) = parse(#"{"nodes":[{"id":"a","model":null,"effort":"high"}]}"#)
        else { return XCTFail() }
        XCTAssertEqual(plan.nodes[0].model, .clear)
        XCTAssertEqual(plan.nodes[0].effort, .set("high"))
        XCTAssertEqual(plan.nodes[0].role, .keep)
    }

    func testUnknownKeyIsAnErrorNamingTheField() {
        guard case .failure(let error) = parse(#"{"nodes":[{"id":"a","modle":"opus"}]}"#)
        else { return XCTFail("campo com erro de digitação passou calado") }
        XCTAssertTrue(error.message.contains("'modle'"), error.message)
        XCTAssertTrue(error.message.contains("nó 'a'"), error.message)
    }

    func testUnknownTopLevelKeyIsAnError() {
        guard case .failure(let error) = parse(#"{"node":[]}"#) else { return XCTFail() }
        XCTAssertTrue(error.message.contains("'node'"), error.message)
    }

    func testBrokenJSONSaysSo() {
        guard case .failure(let error) = parse("{nodes: [") else { return XCTFail() }
        XCTAssertTrue(error.message.contains("JSON inválido"), error.message)
    }

    func testEmptyBodyIsAnError() {
        guard case .failure = parse("") else { return XCTFail() }
    }

    // MARK: - Criar

    func testNewAgentGetsDefaultsAndIsLinkedBothWaysToTheMaestro() {
        let out = plan(#"{"nodes":[{"id":"front","model":"opus","effort":"xhigh","role":"Front."}]}"#)
        XCTAssertEqual(out.errors, [])
        XCTAssertEqual(out.created, ["front"])
        let front = out.next.nodes.first { $0.id == "front" }
        XCTAssertEqual(front?.type, .agent)
        XCTAssertEqual(front?.agent, "claude", "sem cli, o Claude Code")
        XCTAssertEqual(front?.config, "~/.claude-agro", "a configuração que o workspace sugere")
        XCTAssertEqual(front?.prompt, "Front.")
        XCTAssertNil(front?.maestro, "o plano não faz maestro")
        XCTAssertTrue(out.next.edgeList.contains(EdgeConfig(from: "maestro", to: "front")))
        XCTAssertTrue(out.next.edgeList.contains(EdgeConfig(from: "front", to: "maestro")))
        XCTAssertTrue(out.edgesChanged)
    }

    func testPlanCanRaiseTheLimitOfTheAutomaticLink() {
        let out = plan(#"{"nodes":[{"id":"front"}],"edges":[{"from":"maestro","to":"front","both":true,"maxSends":6}]}"#)
        XCTAssertEqual(out.errors, [])
        let edges = out.next.edgeList.filter { $0.from == "front" || $0.to == "front" }
        XCTAssertEqual(edges.count, 2)
        XCTAssertEqual(edges.map(\.maxSends), [6, 6])
    }

    func testShellNodeIsNotLinkedAndRejectsAgentFields() {
        let ok = plan(#"{"nodes":[{"id":"dev","kind":"shell"}]}"#)
        XCTAssertEqual(ok.errors, [])
        XCTAssertNil(ok.next.nodes.last?.cmd)
        XCTAssertFalse(ok.next.edgeList.contains { $0.to == "dev" })

        let bad = plan(#"{"nodes":[{"id":"dev","kind":"shell","model":"opus"}]}"#)
        XCTAssertTrue(bad.errors.contains { $0.contains("'model' é de agente") }, "\(bad.errors)")
    }

    /// Comando de shell escolhido pelo maestro rodaria sem passar pela
    /// permissão do CLI dele: o campo não existe no plano.
    func testShellCommandIsNotAPlanField() {
        guard case .failure(let error) = parse(#"{"nodes":[{"id":"dev","kind":"shell","cmd":"rm -rf ~"}]}"#)
        else { return XCTFail("cmd passou") }
        XCTAssertTrue(error.message.contains("'cmd'"), error.message)
    }

    func testConfigMustBeOneTheCLIKnows() {
        let out = plan(#"{"nodes":[{"id":"x","config":"/tmp/settings-aberto"}]}"#)
        XCTAssertTrue(out.errors.contains { $0.contains("não está entre as de Claude Code") }, "\(out.errors)")
        XCTAssertEqual(plan(#"{"nodes":[{"id":"x","config":"~/.claude"}]}"#).errors, [])
    }

    func testIdMustBeASlug() {
        let out = plan(#"{"nodes":[{"id":"Front End"}]}"#)
        XCTAssertTrue(out.errors.contains { $0.contains("front-end") }, "\(out.errors)")
    }

    // MARK: - Catálogo

    func testUnknownModelIsRefused() {
        let out = plan(#"{"nodes":[{"id":"x","model":"gpt-9"}]}"#)
        XCTAssertTrue(out.errors.contains { $0.contains("modelo 'gpt-9'") }, "\(out.errors)")
    }

    func testEffortMustBelongToTheChosenModel() {
        let out = plan(#"{"nodes":[{"id":"x","model":"sonnet","effort":"max"}]}"#)
        XCTAssertTrue(out.errors.contains { $0.contains("Sonnet 5.5 não tem esforço 'max'") },
                      "\(out.errors)")
        let none = plan(#"{"nodes":[{"id":"x","model":"haiku","effort":"low"}]}"#)
        XCTAssertTrue(none.errors.contains { $0.contains("não tem nível de esforço") }, "\(none.errors)")
        XCTAssertEqual(plan(#"{"nodes":[{"id":"x","model":"opus","effort":"max"}]}"#).errors, [])
        // Trocar só o modelo de um nó com esforço revalida o esforço contra o novo.
        XCTAssertFalse(plan(#"{"nodes":[{"id":"revisor","effort":"high"}]}"#).errors.contains { $0.contains("esforço") })
    }

    func testCLIThatDoesNotTakeModelSaysSo() {
        let out = plan(#"{"nodes":[{"id":"x","cli":"opencode","model":"opus"}]}"#)
        XCTAssertTrue(out.errors.contains { $0.contains("não aceita escolher modelo") }, "\(out.errors)")
    }

    func testUnknownCLIListsTheKnownOnes() {
        let out = plan(#"{"nodes":[{"id":"x","cli":"cursor"}]}"#)
        XCTAssertTrue(out.errors.contains { $0.contains("claude, opencode") }, "\(out.errors)")
    }

    func testMissingFolderIsRefused() {
        let out = plan(#"{"nodes":[{"id":"x","cwd":"web"}]}"#, missing: ["/web"])
        XCTAssertTrue(out.errors.contains { $0.contains("pasta 'web' não existe") }, "\(out.errors)")
    }

    // MARK: - Atualizar

    func testUpdateKeepsWhatIsAbsentAndTheConversation() {
        let out = plan(#"{"nodes":[{"id":"revisor","effort":"high"}]}"#)
        XCTAssertEqual(out.errors, [])
        let revisor = out.next.nodes.first { $0.id == "revisor" }
        XCTAssertEqual(revisor?.model, "sonnet")
        XCTAssertEqual(revisor?.effort, "high")
        XCTAssertEqual(revisor?.prompt, "Revise.")
        XCTAssertEqual(revisor?.conversationId, "conv-revisor", "trocar esforço retoma a conversa")
        XCTAssertEqual(out.restarted, ["revisor"])
    }

    func testNullGoesBackToTheDefault() {
        let out = plan(#"{"nodes":[{"id":"revisor","model":null}]}"#)
        XCTAssertNil(out.next.nodes.first { $0.id == "revisor" }?.model)
    }

    func testSwitchingCLIDropsTheConversation() {
        let out = plan(#"{"nodes":[{"id":"revisor","cli":"opencode","model":null}]}"#)
        XCTAssertEqual(out.errors, [])
        let revisor = out.next.nodes.first { $0.id == "revisor" }
        XCTAssertEqual(revisor?.agent, "opencode")
        XCTAssertNil(revisor?.conversationId, "a conversa é de outro programa")
    }

    func testRoleWrittenByThePlanBeatsTheCLIOverride() {
        var base = bench()
        base.nodes[1].byAgent = ["claude": .init(prompt: "Papel antigo do Claude.")]
        guard case .success(let parsed) = parse(#"{"nodes":[{"id":"revisor","role":"Novo."}]}"#)
        else { return XCTFail() }
        let out = MaestroPlanner.plan(parsed, on: base, context: context())
        XCTAssertEqual(out.next.nodes[1].effectivePrompt, "Novo.")
    }

    func testSameValuesDoNotRestart() {
        let out = plan(#"{"nodes":[{"id":"revisor","model":"sonnet"}]}"#)
        XCTAssertEqual(out.restarted, [])
        XCTAssertFalse(out.changed)
    }

    /// O CLI guarda a conversa por pasta e por configuração: retomar ali falha
    /// calado numa conversa nova, então ela é zerada e a resposta diz.
    func testChangingFolderStartsAFreshConversation() {
        let out = plan(#"{"nodes":[{"id":"revisor","cwd":"api"}]}"#)
        XCTAssertEqual(out.errors, [])
        XCTAssertNil(out.next.nodes.first { $0.id == "revisor" }?.conversationId)
        XCTAssertEqual(out.freshConversation, ["revisor"])
    }

    /// Um nó do usuário com modelo antigo escrito à mão não trava um plano que
    /// só mexe no papel dele.
    func testOnlyWhatChangedIsValidated() {
        var base = bench()
        base.nodes[1].model = "claude-3-opus-legado"
        guard case .success(let parsed) = parse(#"{"nodes":[{"id":"revisor","role":"Outro."}]}"#)
        else { return XCTFail() }
        XCTAssertEqual(MaestroPlanner.plan(parsed, on: base, context: context()).errors, [])
    }

    func testOtherMaestroAndNonTerminalNodesAreOffLimits() {
        var base = bench()
        base.nodes[1].maestro = true
        base.nodes.append(NodeConfig(type: .editor, id: "editor"))
        for json in [#"{"nodes":[{"id":"revisor","role":"x"}]}"#, #"{"remove":["revisor"]}"#,
                     #"{"nodes":[{"id":"editor","role":"x"}]}"#] {
            guard case .success(let parsed) = parse(json) else { return XCTFail() }
            XCTAssertFalse(MaestroPlanner.plan(parsed, on: base, context: context()).errors.isEmpty, json)
        }
    }

    /// O maestro afrouxa os limites até um teto; tirar de vez é do usuário.
    func testChainGuardsHaveACeiling() {
        XCTAssertFalse(plan(#"{"edges":[{"from":"maestro","to":"revisor","maxSends":null}]}"#).errors.isEmpty)
        XCTAssertFalse(plan(#"{"edges":[{"from":"maestro","to":"revisor","maxSends":50}]}"#).errors.isEmpty)
        XCTAssertFalse(plan(#"{"maxVisits":100}"#).errors.isEmpty)
        XCTAssertEqual(plan(#"{"edges":[{"from":"maestro","to":"revisor","maxSends":10}],"maxVisits":12}"#).errors, [])
    }

    func testUnlinkOfARemovedNodeIsNotAnError() {
        XCTAssertEqual(plan(#"{"remove":["revisor"],"unlink":[{"from":"maestro","to":"revisor","both":true}]}"#).errors, [])
    }

    /// Copiar um nó do `egeon bench` para o plano funciona; virar maestro, não.
    func testBenchOnlyKeysAreIgnoredButMaestroIsRefused() {
        guard case .success = parse(#"{"nodes":[{"id":"revisor","state":"idle","you":false,"maestro":false}]}"#)
        else { return XCTFail("chave só de leitura derrubou o plano") }
        guard case .failure(let error) = parse(#"{"nodes":[{"id":"revisor","maestro":true}]}"#)
        else { return XCTFail("maestro pelo plano passou") }
        XCTAssertTrue(error.message.contains("só o usuário"), error.message)
    }

    func testKindDoesNotChange() {
        let out = plan(#"{"nodes":[{"id":"sh","kind":"agent"}]}"#)
        XCTAssertTrue(out.errors.contains { $0.contains("não vira agent") }, "\(out.errors)")
    }

    // MARK: - O maestro e o trabalho dos outros

    func testMaestroCannotTouchItself() {
        XCTAssertTrue(plan(#"{"nodes":[{"id":"maestro","model":"haiku"}]}"#).errors
            .contains { $0.contains("é você") })
        XCTAssertTrue(plan(#"{"remove":["maestro"]}"#).errors.contains { $0.contains("é você") })
    }

    func testBusyNodeIsNotRestartedNorRemoved() {
        let restart = plan(#"{"nodes":[{"id":"revisor","effort":"low"}]}"#, busy: ["revisor"])
        XCTAssertTrue(restart.errors.contains { $0.contains("trabalhando agora: revisor") }, "\(restart.errors)")
        let remove = plan(#"{"remove":["revisor"]}"#, busy: ["revisor"])
        XCTAssertTrue(remove.errors.contains { $0.contains("trabalhando agora") })
        // Mexer só em aresta não reinicia ninguém.
        XCTAssertEqual(plan(#"{"edges":[{"from":"maestro","to":"revisor","maxSends":5}]}"#,
                            busy: ["revisor"]).errors, [])
    }

    /// Segundo plano é ambíguo — esperando vizinho ou processo rodando —, e
    /// quem olha é o maestro: recusa, mas `force` passa. Turno em curso nunca.
    func testBackgroundNodeNeedsForceButWorkingNeverPasses() {
        let refused = plan(#"{"remove":["revisor"]}"#, background: ["revisor"])
        XCTAssertTrue(refused.errors.contains { $0.contains("em segundo plano: revisor") }, "\(refused.errors)")
        XCTAssertTrue(refused.errors.contains { $0.contains("\"force\": true") })
        XCTAssertEqual(plan(#"{"remove":["revisor"],"force":true}"#, background: ["revisor"]).errors, [])
        XCTAssertFalse(plan(#"{"remove":["revisor"],"force":true}"#, busy: ["revisor"]).errors.isEmpty)
    }

    func testBenchRulesRestartTheOtherAgentsButNotTheMaestro() {
        let out = plan(#"{"rules":"Peça antes de commitar."}"#)
        XCTAssertEqual(out.errors, [])
        XCTAssertEqual(out.next.rules, "Peça antes de commitar.")
        XCTAssertEqual(out.restarted, ["revisor"], "shell não lê regra, e o maestro não reinicia")
        XCTAssertTrue(out.rulesChanged)
    }

    // MARK: - Remover e arestas

    func testRemovingTakesItsEdgesAlong() {
        let out = plan(#"{"remove":["revisor"]}"#)
        XCTAssertEqual(out.removed, ["revisor"])
        XCTAssertFalse(out.next.nodes.contains { $0.id == "revisor" })
        XCTAssertEqual(out.next.edgeList, [])
    }

    func testEdgeToMissingNodeIsRefused() {
        let out = plan(#"{"edges":[{"from":"maestro","to":"fantasma"}]}"#)
        XCTAssertTrue(out.errors.contains { $0.contains("'fantasma' não existe") }, "\(out.errors)")
    }

    func testUnlinkBoth() {
        let out = plan(#"{"unlink":[{"from":"maestro","to":"revisor","both":true}]}"#)
        XCTAssertEqual(out.errors, [])
        XCTAssertEqual(out.next.edgeList, [])
    }

    func testErrorsAccumulateInsteadOfStoppingAtTheFirst() {
        let out = plan(#"{"nodes":[{"id":"a","model":"gpt-9"},{"id":"b","cli":"cursor"}],"maxVisits":0}"#)
        XCTAssertGreaterThanOrEqual(out.errors.count, 3, "\(out.errors)")
    }

    func testSummaryReadsLikeTheTrace() {
        let out = plan(#"{"nodes":[{"id":"front"},{"id":"revisor","effort":"low"}],"remove":["sh"]}"#)
        XCTAssertEqual(out.errors, [])
        XCTAssertTrue(out.summary.hasPrefix("+front ~revisor −sh"), out.summary)
    }
}
