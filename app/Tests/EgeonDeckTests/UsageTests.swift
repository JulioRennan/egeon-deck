import XCTest
@testable import EgeonDeck

final class UsageTests: XCTestCase {
    private func line(id: String, model: String = "claude-opus-5-5", input: Int = 10, output: Int = 100,
                      write5m: Int = 0, write1h: Int = 0, read: Int = 0, speed: String = "standard",
                      text: String = "oi") -> String {
        """
        {"type":"assistant","message":{"id":"\(id)","model":"\(model)","content":[{"type":"text","text":"\(text)"}],\
        "usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_creation_input_tokens":\(write5m + write1h),\
        "cache_read_input_tokens":\(read),"cache_creation":{"ephemeral_5m_input_tokens":\(write5m),\
        "ephemeral_1h_input_tokens":\(write1h)},"speed":"\(speed)"}}}
        """
    }

    func testEntriesCountEachMessageOnce() {
        let jsonl = [line(id: "a", write1h: 30), line(id: "a", write1h: 30), line(id: "b", read: 500),
                     #"{"type":"user","message":{"content":"x"}}"#,
                     line(id: "c", model: "<synthetic>")].joined(separator: "\n") + "\n"
        let entries = ClaudeUsage.entries(in: Data(jsonl.utf8))
        XCTAssertEqual(entries.map(\.id), ["a", "b"])
        XCTAssertEqual(entries[0].usage, TokenUsage(input: 10, output: 100, cacheWrite1h: 30))
        // A leitura que parte no meio das linhas de "a" não a conta de novo.
        XCTAssertEqual(ClaudeUsage.entries(in: Data(jsonl.utf8), after: "a").map(\.id), ["b"])
    }

    func testCacheWriteWithoutSplitIsFiveMinutes() {
        let raw = #"{"type":"assistant","message":{"id":"x","model":"claude-sonnet-5-5","usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":40,"cache_read_input_tokens":0}}}"#
        XCTAssertEqual(ClaudeUsage.entry(fromLine: Data(raw.utf8))?.usage.cacheWrite5m, 40)
    }

    func testPriceKeysAndCost() {
        let prices = PriceTable(models: PriceTable.builtIn)
        let opus = UsageEntry(id: "1", model: "claude-opus-5-5",
                              usage: TokenUsage(input: 1_000_000, output: 1_000_000, cacheWrite5m: 1_000_000,
                                                cacheWrite1h: 1_000_000, cacheRead: 1_000_000))
        XCTAssertEqual(prices.key(for: opus), "claude-opus-5-5")
        // 4 + 20 + 5 (1,25×) + 8 (2×) + 0,20
        XCTAssertEqual(prices.cost([prices.key(for: opus): opus.usage]).dollars, 37.2, accuracy: 0.0001)

        var fast = opus
        fast.fast = true
        XCTAssertEqual(prices.key(for: fast), "claude-opus-5-5#fast")
        XCTAssertEqual(prices.cost(["claude-opus-5-5#fast": opus.usage]).dollars, 74.4, accuracy: 0.0001)

        let short = UsageEntry(id: "2", model: "claude-haiku-5-5", usage: TokenUsage(input: 90_000))
        let long = UsageEntry(id: "3", model: "claude-haiku-5-5", usage: TokenUsage(input: 1_000, cacheRead: 150_000))
        XCTAssertEqual(prices.key(for: short), "claude-haiku-5-5")
        XCTAssertEqual(prices.key(for: long), "claude-haiku-5-5#long")

        XCTAssertEqual(PriceTable.canonical("claude-haiku-4-5-20251001"), "claude-haiku-4-5")
        let unknown = prices.cost(["claude-futuro-9": TokenUsage(input: 5)])
        XCTAssertTrue(unknown.unpriced)
        XCTAssertEqual(unknown.dollars, 0)
    }

    func testLedgerReadsOnlyCompleteLinesAndKeepsTheCursor() {
        let prices = PriceTable(models: PriceTable.builtIn)
        var ledger = UsageLedger()
        let first = line(id: "a") + "\n" + line(id: "a") + "\n"
        let partial = String(line(id: "b").prefix(30))
        ledger.absorb(chunk: Data((first + partial).utf8), of: "/t.jsonl", node: "dev", prices: prices) {
            ClaudeUsage.entries(in: $0, after: $1)
        }
        XCTAssertEqual(ledger.cursors["/t.jsonl"], .init(offset: UInt64(first.utf8.count), lastId: "a"))
        XCTAssertEqual(ledger.byNode["dev"]?.totalUsage.output, 100)

        // O resto do arquivo: a mensagem "a" que continua não conta de novo.
        let rest = line(id: "a") + "\n" + line(id: "b", output: 7) + "\n"
        ledger.absorb(chunk: Data(rest.utf8), of: "/t.jsonl", node: "dev", prices: prices) {
            ClaudeUsage.entries(in: $0, after: $1)
        }
        XCTAssertEqual(ledger.byNode["dev"]?.totalUsage.output, 107)
        XCTAssertEqual(ledger.total.totalUsage.output, 107)
    }

    func testTraceConversations() {
        let trace = """
        # bancada

        ## 2026-09-03 17:03 · claude
        Claude Code · claude-opus-5 · conversa fc431fec

        pedido: x
        ## 2026-09-03 18:00 · terminal
        $ ls
        ## 2026-09-04 09:00 · revisor
        Claude Code · claude-opus-5-5 · conversa 1B1FCD63
        ## 2026-09-04 10:00 · claude
        Claude Code · claude-opus-5 · conversa fc431fec
        """
        let found = TraceConversations.parse(trace)
        XCTAssertEqual(found.map(\.node), ["claude", "revisor"])
        XCTAssertEqual(found.map(\.prefix), ["fc431fec", "1B1FCD63"])
    }

    func testTurnCarriesItsUsage() {
        let jsonl = [
            #"{"type":"user","uuid":"u1","timestamp":"2026-10-22T10:00:00Z","message":{"content":"faz"}}"#,
            line(id: "m1", write1h: 50, text: "feito"), line(id: "m1", write1h: 50, text: "feito"),
            line(id: "m2", read: 70, text: "mais"),
            #"{"type":"user","uuid":"u2","timestamp":"2026-10-22T10:05:00Z","message":{"content":"de novo"}}"#,
            line(id: "m3", output: 3, text: "ok"),
        ].joined(separator: "\n")
        let turns = ClaudeTranscript.parse(jsonl)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].usage.totalUsage, TokenUsage(input: 20, output: 200, cacheWrite1h: 50, cacheRead: 70))
        XCTAssertEqual(turns[1].usage.totalUsage.output, 3)

        // Vai e volta do histórico do chat com o uso junto.
        let data = try! JSONEncoder().encode(turns[0])
        XCTAssertEqual(try! JSONDecoder().decode(ChatTurn.self, from: data).usage, turns[0].usage)
    }

    func testMoneyText() {
        XCTAssertEqual(UsageText.dollars(10.4), "US$ 10,40")
        XCTAssertEqual(UsageText.dollars(0.6007), "US$ 0,60")
        XCTAssertEqual(UsageText.dollars(0.004), "< US$ 0,01")
        XCTAssertEqual(UsageText.dollars(1234.5), "US$ 1.234,50")
        XCTAssertEqual(UsageText.tokens(17_080_000), "17,08M")
    }
}
