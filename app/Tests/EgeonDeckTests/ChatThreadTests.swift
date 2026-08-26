import XCTest
@testable import EgeonDeck

/// O JSONL do Claude Code vira turnos: prompt seu + passos + texto final.
final class ClaudeTranscriptTests: XCTestCase {
    private let sample = """
    {"type":"attachment","timestamp":"2026-08-24T23:13:11.000Z","message":{"content":"x"}}
    {"parentUuid":"a1","isSidechain":false,"userType":"external","cwd":"/x","sessionId":"s","version":"2.1","gitBranch":"main","type":"user","timestamp":"2026-08-24T23:13:27.000Z","message":{"role":"user","content":"echo egeon-chat-ok"}}
    {"type":"assistant","timestamp":"2026-08-24T23:13:31.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"echo egeon-chat-ok","description":"Ecoa a marca"}}]}}
    {"type":"user","timestamp":"2026-08-24T23:13:32.000Z","message":{"content":[{"type":"tool_result","content":"egeon-chat-ok"}]}}
    {"type":"assistant","timestamp":"2026-08-24T23:13:33.000Z","message":{"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a/b/app/Main.swift"}}]}}
    {"type":"assistant","timestamp":"2026-08-24T23:13:35.000Z","message":{"content":[{"type":"text","text":"`egeon-chat-ok`\\n\\n[[ED:ok]]"}]}}
    {"type":"user","timestamp":"2026-08-24T23:14:00.000Z","message":{"content":"<command-name>/clear</command-name>"}}
    {"type":"user","timestamp":"2026-08-24T23:15:00.000Z","message":{"content":[{"type":"text","text":"oi"}]}}
    """

    func testParsesPromptStepsAndReply() {
        let turns = ClaudeTranscript.parse(sample)
        XCTAssertEqual(turns.count, 2)

        let first = turns[0]
        XCTAssertEqual(first.prompt, "echo egeon-chat-ok")
        XCTAssertEqual(first.steps.map { "\($0.glyph) \($0.text)" }, ["$ Ecoa a marca", "± app/Main.swift"])
        XCTAssertEqual(first.steps[0].detail, "echo egeon-chat-ok")
        // Marcador do protocolo é do app, não da bolha.
        XCTAssertEqual(first.replyText, "`egeon-chat-ok`")
        XCTAssertNotNil(first.replyAt)
        XCTAssertTrue(first.hasReply)

        // Comando de barra não é prompt; o "oi" em bloco de texto é.
        XCTAssertEqual(turns[1].prompt, "oi")
        XCTAssertFalse(turns[1].hasReply)
    }

    // A cadeia guarda a ORDEM: prosa, passos, prosa — é ela que a bolha
    // desenha, e não "todos os passos, depois todo o texto" (ADR-039).
    func testChainKeepsProseAndStepsInOrder() {
        let jsonl = """
        {"type":"user","uuid":"u1","timestamp":"2026-08-24T23:13:27.000Z","message":{"content":"faz"}}
        {"type":"assistant","timestamp":"2026-08-24T23:13:28.000Z","message":{"content":[{"type":"text","text":"Vou olhar."}]}}
        {"type":"assistant","timestamp":"2026-08-24T23:13:29.000Z","message":{"content":[{"type":"thinking","thinking":"hmm"}]}}
        {"type":"assistant","timestamp":"2026-08-24T23:13:30.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls","description":"Lista"}}]}}
        {"type":"assistant","timestamp":"2026-08-24T23:13:31.000Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/a/b.swift"}}]}}
        {"type":"assistant","timestamp":"2026-08-24T23:13:32.000Z","message":{"content":[{"type":"text","text":"Achei.\\n\\n[[ED:ok]]"}]}}
        """
        let parsed = ClaudeTranscript.parseDetailed(jsonl)
        let turn = parsed.turns[0]
        XCTAssertEqual(turn.parts, [.text("Vou olhar."),
                                    .step(ChatStep(glyph: "$", text: "Lista", detail: "ls")),
                                    .step(ChatStep(glyph: "→", text: "read a/b.swift")),
                                    .text("Achei.")])
        XCTAssertEqual(turn.chain, turn.parts)
        XCTAssertEqual(turn.lastText, "Achei.")
        // As somas continuam valendo para citação, troca e histórico antigo.
        XCTAssertEqual(turn.replyText, "Vou olhar.\n\nAchei.")
        XCTAssertEqual(turn.steps.count, 2)
        XCTAssertEqual(parsed.last, .text)
    }

    // Registro gravado antes da cadeia existir: a bolha reconstrói na forma
    // antiga — passos, depois o texto — e o decode não derruba a linha.
    func testTurnWithoutPartsDecodesAndRebuildsChain() throws {
        let json = """
        {"id":"t1","prompt":"oi","promptAt":"2026-08-24T23:13:27.000Z","steps":[{"glyph":"$","text":"ls"}],"replyText":"feito","exchanges":[]}
        """
        let turn = try ChatHistory.decoder.decode(ChatTurn.self, from: Data(json.utf8))
        XCTAssertTrue(turn.parts.isEmpty)
        XCTAssertEqual(turn.chain, [.step(ChatStep(glyph: "$", text: "ls")), .text("feito")])
        let data = try ChatHistory.encoder.encode(turn)
        let back = try ChatHistory.decoder.decode(ChatTurn.self, from: data)
        XCTAssertEqual(back, turn)
    }

    func testChainPartsRoundTripWithSendTarget() throws {
        var turn = ChatTurn(id: "t1", prompt: "oi", promptAt: Date(timeIntervalSince1970: 1_000))
        turn.parts = [.text("vou mandar"),
                      .step(ChatStep(glyph: "⇄", text: "egeon send deck/b", sendTo: "deck/b"))]
        let data = try ChatHistory.encoder.encode(turn)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"kind\":\"step\""))
        XCTAssertEqual(try ChatHistory.decoder.decode(ChatTurn.self, from: data).parts, turn.parts)
    }

    // O leitor ao vivo: a cadeia até onde o CLI gravou, e o que ele fazia no
    // fim — ferramenta em curso ou raciocínio. Turno mais velho que o prompt
    // deste é o turno passado: nil, e a bolha fica em "trabalhando…".
    func testLiveTurnReportsWhatIsHappeningNow() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("live-\(UUID()).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let jsonl = """
        {"type":"user","uuid":"u1","timestamp":"2026-08-25T17:00:00.000Z","message":{"content":"faz"}}
        {"type":"assistant","timestamp":"2026-08-25T17:00:01.000Z","message":{"content":[{"type":"text","text":"Vou olhar."}]}}
        {"type":"assistant","timestamp":"2026-08-25T17:00:02.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test","description":"Roda os testes"}}]}}
        """
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
        let iso = ISO8601DateFormatter()
        let live = try XCTUnwrap(ClaudeTranscript.liveTurn(
            at: url, notBefore: iso.date(from: "2026-08-25T17:00:03Z")))
        XCTAssertEqual(live.turn.id, "u1")
        XCTAssertEqual(live.last, .tool)
        XCTAssertEqual(live.turn.parts.count, 2)

        // Prompt novo veio depois do que o arquivo tem: é o turno passado.
        XCTAssertNil(ClaudeTranscript.liveTurn(at: url, notBefore: iso.date(from: "2026-08-25T17:05:00Z")))

        try (jsonl + "\n" + """
        {"type":"assistant","timestamp":"2026-08-25T17:00:03.000Z","message":{"content":[{"type":"thinking","thinking":"…"}]}}
        """).write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(ClaudeTranscript.liveTurn(at: url, notBefore: nil)?.last, .thinking)
    }

    // Mensagem de outro agente chega envelopada pelo Dispatcher: sai o
    // remetente e só o texto, sem o cabeçalho.
    func testAgentEnvelopeIsUnwrapped() {
        let wrapped = """
        [egeon] mensagem de deck/front

        o /nodes devolve o estado calculado?
        """
        let envelope = ClaudeTranscript.agentEnvelope(wrapped)
        XCTAssertEqual(envelope?.from, "deck/front")
        XCTAssertEqual(envelope?.text, "o /nodes devolve o estado calculado?")
        XCTAssertNil(ClaudeTranscript.agentEnvelope("oi"))
    }

    func testSendStepCarriesTarget() {
        XCTAssertEqual(ClaudeTranscript.sendTarget(in: "egeon send deck/back <<'MB'\nveja isso\nMB"),
                       "deck/back")
        XCTAssertNil(ClaudeTranscript.sendTarget(in: "egeon peers"))
    }

    func testAssistantBeforeAnyPromptIsIgnored() {
        let orphan = """
        {"type":"assistant","timestamp":"2026-08-24T23:13:35.000Z","message":{"content":[{"type":"text","text":"solto"}]}}
        """
        XCTAssertTrue(ClaudeTranscript.parse(orphan).isEmpty)
    }
}

/// A thread cruza os agentes por tempo e tira o eco quando o transcript chega.
final class ChatThreadTests: XCTestCase {
    private func agent(_ id: String) -> ChatParticipant {
        ChatParticipant(id: id, address: "deck/\(id)", isAgent: true, role: nil, activity: .ready)
    }

    func testBuildInterleavesByTime() {
        let base = Date(timeIntervalSince1970: 1_000)
        let front = agent("front"), back = agent("back")
        var frontTurn = ChatTurn(id: "f1", prompt: "faz a coluna", promptAt: base)
        frontTurn.replyText = "feita"; frontTurn.replyAt = base.addingTimeInterval(30)
        let backTurn = ChatTurn(id: "b1", prompt: "expõe /nodes", promptAt: base.addingTimeInterval(10))

        let shell = ChatParticipant(id: "zsh", address: "deck/zsh", isAgent: false,
                                    role: nil, activity: .ready)
        // Shell não tem transcript: mesmo que a fechadura devolva algo, fica fora.
        let thread = ChatThread.build(participants: [front, back, shell]) {
            switch $0.id {
            case "front": return [frontTurn]
            case "back":  return [backTurn]
            default:      return [ChatTurn(id: "z", prompt: "nunca", promptAt: base)]
            }
        }

        XCTAssertEqual(thread.count, 3)
        XCTAssertEqual(thread[0], .prompt(to: front, turnId: "f1", text: "faz a coluna", at: base))
        // Prompt ao back logo depois de prompt ao front: o back ainda não falou,
        // não há o que citar.
        XCTAssertEqual(thread[1], .prompt(to: back, turnId: "b1", text: "expõe /nodes",
                                          at: base.addingTimeInterval(10)))
        // A resposta do front NÃO vem logo depois do prompt dela (o prompt ao
        // back entrou no meio): cita o prompt, estilo WhatsApp.
        guard case .reply(let from, let turn, let quote) = thread[2] else {
            return XCTFail("esperava resposta do front")
        }
        XCTAssertEqual(from, front)
        XCTAssertEqual(turn, frontTurn)
        XCTAssertEqual(quote?.authorId, nil)
        XCTAssertEqual(quote?.text, "faz a coluna")
        XCTAssertEqual(quote?.targetKey, thread[0].key)
    }

    // Consecutivo é limpo: prompt e resposta um atrás do outro, sem citação.
    func testConsecutiveReplyHasNoQuote() {
        let front = agent("front")
        let base = Date(timeIntervalSince1970: 1_000)
        var turn = ChatTurn(id: "t1", prompt: "oi", promptAt: base)
        turn.replyText = "oi"; turn.replyAt = base.addingTimeInterval(5)
        let thread = ChatThread.build(participants: [front]) { _ in [turn] }
        XCTAssertNil(thread[1].quote)
    }

    // Meu prompt intercalado cita a última fala do agente a quem falo.
    func testInterleavedPromptQuotesAgentsLastReply() {
        let front = agent("front"), back = agent("back")
        let base = Date(timeIntervalSince1970: 1_000)
        var backTurn = ChatTurn(id: "b1", prompt: "expõe", promptAt: base)
        backTurn.replyText = "no ar"; backTurn.replyAt = base.addingTimeInterval(5)
        let frontTurn = ChatTurn(id: "f1", prompt: "faz", promptAt: base.addingTimeInterval(10))
        let later = ChatTurn(id: "b2", prompt: "adiciona lastActivity", promptAt: base.addingTimeInterval(20))

        let thread = ChatThread.build(participants: [front, back]) {
            $0.id == "back" ? [backTurn, later] : [frontTurn]
        }
        // back: expõe, no ar · front: faz · back: adiciona (intercalado → cita "no ar")
        XCTAssertEqual(thread.count, 4)
        XCTAssertEqual(thread[3].quote?.authorId, "back")
        XCTAssertEqual(thread[3].quote?.text, "no ar")
        XCTAssertEqual(thread[3].quote?.targetKey, thread[1].key)
        XCTAssertNil(thread[2].quote, "front ainda não falou: nada a citar")
    }

    func testPendingDropsWhatTranscriptConfirmed() {
        let front = agent("front")
        let now = Date()
        let messages: [ChatMessage] = [.prompt(to: front, turnId: "u2", text: "oi", at: now)]
        let left = ChatThread.stillPending([
            .init(text: "oi", target: "front", sentAt: now, knownTurnIds: ["u1"]),
            .init(text: "oi", target: "back", sentAt: now, knownTurnIds: []),
            .init(text: "tchau", target: "front", sentAt: now, knownTurnIds: ["u1"]),
        ], given: messages)
        XCTAssertEqual(left.map(\.text), ["oi", "tchau"])
        XCTAssertEqual(left.map(\.target), ["back", "front"])
    }

    // Sub-conversa: front pergunta ao back via egeon send; o back recebe (turno
    // "de front"), responde via egeon send; o front recebe a volta e continua.
    // Na thread: UMA bolha do front, com as duas trocas dentro e a continuação
    // como corpo. Nada disso vira bolha de topo.
    func testAgentExchangesFoldIntoOwnersBubble() {
        let front = agent("front"), back = agent("back")
        let base = Date(timeIntervalSince1970: 1_000)

        var root = ChatTurn(id: "f1", prompt: "faz a coluna", promptAt: base)
        root.steps = [ChatStep(glyph: "⇄", text: "egeon send deck/back", sendTo: "deck/back")]
        root.replyAt = base.addingTimeInterval(5)

        var backTurn = ChatTurn(id: "b1", prompt: "o estado vem pronto?",
                                promptAt: base.addingTimeInterval(10), from: "deck/front")
        backTurn.steps = [ChatStep(glyph: "⇄", text: "egeon send deck/front", sendTo: "deck/front")]
        backTurn.replyText = "Respondi ao front."
        backTurn.replyAt = base.addingTimeInterval(15)

        var frontBack = ChatTurn(id: "f2", prompt: "vem pronto: state ∈ {…}",
                                 promptAt: base.addingTimeInterval(20), from: "deck/back")
        frontBack.steps = [ChatStep(glyph: "±", text: "Column.swift")]
        frontBack.replyText = "Coluna pronta, ligada no endpoint."
        frontBack.replyAt = base.addingTimeInterval(30)

        let thread = ChatThread.build(participants: [front, back]) {
            $0.id == "front" ? [root, frontBack] : [backTurn]
        }

        XCTAssertEqual(thread.count, 2, "só prompt seu + bolha do front")
        guard case .reply(let from, let turn, _) = thread[1] else { return XCTFail("esperava resposta") }
        XCTAssertEqual(from, front)
        XCTAssertEqual(turn.exchanges.map { "\($0.fromId)→\($0.toId)" }, ["front→back", "back→front"])
        XCTAssertEqual(turn.exchanges[0].text, "o estado vem pronto?")
        XCTAssertEqual(turn.exchanges[0].note, "Respondi ao front.")
        XCTAssertEqual(turn.exchanges[0].steps, 1)
        XCTAssertEqual(turn.exchanges[1].note, "", "o dono não anota: o que ele disse é o corpo")
        XCTAssertEqual(turn.replyText, "Coluna pronta, ligada no endpoint.")
        XCTAssertEqual(turn.steps.count, 2, "os passos da continuação somam aos do turno")
        XCTAssertEqual(turn.replyAt, base.addingTimeInterval(30))
    }

    // Mensagem de agente sem dono conhecido fica no topo — não some.
    // A volta que o dono da bolha recebeu e continuou: a cadeia dele soma à
    // do turno-raiz, na ordem — não só as somas de passos e texto.
    func testOwnersContinuationAppendsToChain() {
        let base = Date(timeIntervalSince1970: 1_000)
        let front = agent("front"), back = agent("back")
        var root = ChatTurn(id: "f1", prompt: "faz", promptAt: base)
        root.parts = [.text("vou pedir"),
                      .step(ChatStep(glyph: "⇄", text: "egeon send deck/back", sendTo: "deck/back"))]
        root.steps = [ChatStep(glyph: "⇄", text: "egeon send deck/back", sendTo: "deck/back")]
        root.replyText = "vou pedir"; root.replyAt = base.addingTimeInterval(5)
        var backTurn = ChatTurn(id: "b1", prompt: "expõe", promptAt: base.addingTimeInterval(10),
                                from: "deck/front")
        backTurn.replyText = "exposto"; backTurn.replyAt = base.addingTimeInterval(20)
        var back2front = ChatTurn(id: "f2", prompt: "exposto", promptAt: base.addingTimeInterval(21),
                                  from: "deck/back")
        back2front.parts = [.step(ChatStep(glyph: "±", text: "a.swift")), .text("pronto")]
        back2front.steps = [ChatStep(glyph: "±", text: "a.swift")]
        back2front.replyText = "pronto"; back2front.replyAt = base.addingTimeInterval(30)

        let folded = ChatMessage.fold(agents: [front, back],
                                      turns: ["front": [root, back2front], "back": [backTurn]])
        XCTAssertEqual(folded.count, 1)
        // As trocas entram na cadeia (teste próprio abaixo); o resto é a
        // cadeia do raiz seguida da continuação do dono, na ordem.
        let withoutExchanges = folded[0].1.chain.filter { if case .exchange = $0 { return false } else { return true } }
        XCTAssertEqual(withoutExchanges, root.parts + back2front.parts)
        XCTAssertEqual(folded[0].1.exchanges.count, 2)
    }

    // A troca entra na cadeia onde aconteceu: a ida logo depois do `⇄` que a
    // disparou, a volta depois dela, e a continuação do dono depois de tudo —
    // não "toda a conversa com o vizinho depois da resposta final".
    func testExchangesSitInTheChainWhereTheyHappened() {
        let base = Date(timeIntervalSince1970: 1_000)
        let front = agent("front"), back = agent("back")
        let send = ChatStep(glyph: "⇄", text: "egeon send deck/back", sendTo: "deck/back")
        var root = ChatTurn(id: "f1", prompt: "faz", promptAt: base)
        root.parts = [.text("vou pedir"), .step(send), .text("pedi")]
        root.steps = [send]; root.replyText = "vou pedir\n\npedi"; root.replyAt = base.addingTimeInterval(5)
        var backTurn = ChatTurn(id: "b1", prompt: "expõe", promptAt: base.addingTimeInterval(10),
                                from: "deck/front")
        backTurn.replyText = "exposto"; backTurn.replyAt = base.addingTimeInterval(20)
        var reply = ChatTurn(id: "f2", prompt: "exposto", promptAt: base.addingTimeInterval(21),
                             from: "deck/back")
        reply.parts = [.text("pronto")]; reply.replyText = "pronto"; reply.replyAt = base.addingTimeInterval(30)

        let folded = ChatMessage.fold(agents: [front, back],
                                      turns: ["front": [root, reply], "back": [backTurn]])
        let kinds = folded[0].1.chain.map { part -> String in
            switch part {
            case .text(let t): return "¶\(t)"
            case .step: return "⇄"
            case .exchange(let e): return "\(e.fromId)→\(e.toId)"
            }
        }
        XCTAssertEqual(kinds, ["¶vou pedir", "⇄", "front→back", "¶pedi", "back→front", "¶pronto"])
    }

    func testSendTargetIgnoresHeredocNoise() {
        XCTAssertEqual(ClaudeTranscript.sendTarget(in: "egeon send deck/b <<'MB'\noi\nMB"), "deck/b")
        XCTAssertEqual(ClaudeTranscript.sendTarget(in: "egeon   send\tback <<'MB'\nMB"), "back")
        XCTAssertNil(ClaudeTranscript.sendTarget(in: "egeon send <<'MB'\nsend\nMB"))
        XCTAssertNil(ClaudeTranscript.sendTarget(in: "egeon send\ndeck/b"))
    }

    func testExchangePartRoundTrips() throws {
        let exchange = ChatExchange(fromId: "a", toId: "b", text: "oi", at: Date(timeIntervalSince1970: 5),
                                    steps: 2, note: "feito")
        let data = try ChatHistory.encoder.encode(ChatPart.exchange(exchange))
        XCTAssertEqual(try ChatHistory.decoder.decode(ChatPart.self, from: data), .exchange(exchange))
    }

    func testOrphanExchangeStaysOnTop() {
        let back = agent("back")
        let turn = ChatTurn(id: "b1", prompt: "oi", promptAt: Date(), from: "outra/coisa")
        let thread = ChatThread.build(participants: [back]) { _ in [turn] }
        XCTAssertEqual(thread.count, 1)
        XCTAssertEqual(thread[0].promptText, "de outra/coisa: oi")
    }

    // O eco entra NA linha do tempo pela hora do envio: resposta que chega
    // depois dele fica embaixo, não em cima de um eco pinado no rodapé.
    func testPendingEchoSitsInTimeline() {
        let front = agent("front"), back = agent("back")
        let base = Date(timeIntervalSince1970: 1_000)
        var frontTurn = ChatTurn(id: "f1", prompt: "oi", promptAt: base)
        frontTurn.replyText = "oi"; frontTurn.replyAt = base.addingTimeInterval(8)
        let echo = ChatThread.Pending(text: "oi", target: "back",
                                      sentAt: base.addingTimeInterval(3), knownTurnIds: [])

        let built = ChatThread.build(participants: [front, back], pending: [echo]) {
            $0.id == "front" ? [frontTurn] : []
        }
        XCTAssertEqual(built.pending.map(\.text), ["oi"])
        // O turno do front foi visto e virou conhecido para o eco do back.
        XCTAssertEqual(built.pending.first?.knownTurnIds, ["f1"])
        XCTAssertEqual(built.messages.map(\.key),
                       ["p|f1", "e|back|1003.0", "r|f1"])
    }

    // Dois "oi" seguidos: o primeiro turno novo dá baixa em UM eco, não nos dois.
    func testOneNewTurnConfirmsOnePending() {
        let front = agent("front")
        let now = Date()
        let messages: [ChatMessage] = [.prompt(to: front, turnId: "u2", text: "oi", at: now)]
        let left = ChatThread.stillPending([
            .init(text: "oi", target: "front", sentAt: now, knownTurnIds: ["u1"]),
            .init(text: "oi", target: "front", sentAt: now, knownTurnIds: ["u1"]),
        ], given: messages)
        XCTAssertEqual(left.count, 1)
        // Rodada seguinte, mesma lista: o turno já usado não dá baixa de novo.
        XCTAssertEqual(ChatThread.stillPending(left, given: messages).count, 1)
        // Só o segundo turno novo fecha o segundo eco.
        let more = messages + [.prompt(to: front, turnId: "u3", text: "oi", at: now)]
        XCTAssertEqual(ChatThread.stillPending(left, given: more).count, 0)
    }

    // Um "oi" que JÁ existia na hora do envio não confirma o "oi" novo — nem que
    // tenha sido gravado há um segundo. Só id que o envio ainda não conhecia.
    func testKnownTurnDoesNotConfirmNewPending() {
        let front = agent("front")
        let now = Date()
        let messages: [ChatMessage] = [.prompt(to: front, turnId: "u1", text: "oi", at: now)]
        let left = ChatThread.stillPending(
            [.init(text: "oi", target: "front", sentAt: now, knownTurnIds: ["u1"])],
            given: messages)
        XCTAssertEqual(left.count, 1)
    }
}
