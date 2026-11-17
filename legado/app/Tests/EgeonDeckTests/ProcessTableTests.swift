import XCTest
@testable import EgeonDeck

final class ProcessTableTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func raw(_ pid: Int32, _ ppid: Int32, _ name: String = "node", at offset: TimeInterval = 0,
                     _ environment: [String: String] = [:]) -> RawProcess {
        RawProcess(pid: pid, ppid: ppid, started: t0.addingTimeInterval(offset), name: name,
                   command: name, environment: environment)
    }

    private func mark(_ node: String, deck: String? = "egeon") -> [String: String] {
        var env = [ProcessMark.node: node]
        env[ProcessMark.deck] = deck
        return env
    }

    func testDescendantsOfTheAppAreOwnedAndInheritTheNode() {
        let all = [
            raw(1, 0, "launchd"),
            raw(100, 1, "EgeonDeck"),
            raw(101, 100, "zsh", mark("deck/claude")),
            // Limpou o ambiente: ainda é do nó pela árvore.
            raw(102, 101, "chrome"),
            raw(103, 100, "claude"),
        ]
        let found = ProcessTable.classify(all, app: 100, deck: "egeon")
        XCTAssertEqual(found.map(\.pid).sorted(), [101, 102, 103])
        XCTAssertTrue(found.allSatisfy { !$0.orphan })
        XCTAssertEqual(found.first { $0.pid == 102 }?.node, "deck/claude")
        XCTAssertNil(found.first { $0.pid == 103 }?.node)
    }

    func testUnreadableShellTakesTheNodeFromItsChild() {
        let all = [
            raw(1, 0, "launchd"),
            raw(100, 1, "EgeonDeck"),
            raw(101, 100, "zsh"),
            raw(102, 101, "claude", mark("deck/claude")),
        ]
        let found = ProcessTable.classify(all, app: 100, deck: "egeon")
        XCTAssertEqual(found.first { $0.pid == 101 }?.node, "deck/claude")
    }

    func testMarkedProcessOutsideTheAppIsAnOrphanWithItsChildren() {
        let all = [
            raw(1, 0, "launchd"),
            raw(100, 1, "EgeonDeck"),
            raw(200, 1, "node", at: 10, mark("x/claude")),
            raw(201, 200, "chrome", at: 11),
            raw(300, 1, "vim"),
        ]
        let found = ProcessTable.classify(all, app: 100, deck: "egeon")
        XCTAssertEqual(found.map(\.pid).sorted(), [200, 201])
        XCTAssertTrue(found.allSatisfy(\.orphan))
        XCTAssertEqual(found.first { $0.pid == 201 }?.node, "x/claude")
    }

    func testOtherFlavorAndItsTreeAreNotOurs() {
        let all = [
            raw(1, 0, "launchd"),
            raw(100, 1, "EgeonDeck"),
            // O outro app herdou a marca de quem o lançou; nem ele nem os
            // filhos dele são órfãos daqui.
            raw(500, 1, "EgeonDeck", mark("deck/claude")),
            raw(501, 500, "zsh", mark("dev/a", deck: "egeon-dev")),
            raw(600, 1, "node", mark("dev/b", deck: "egeon-dev")),
        ]
        XCTAssertEqual(ProcessTable.classify(all, app: 100, deck: "egeon"), [])
    }

    func testAppOpenedFromATerminalIsNotAnOrphan() {
        var docker = mark("x/back")
        docker[ProcessMark.bundleVariable] = "com.docker.docker"
        var server = mark("x/back")
        server[ProcessMark.bundleVariable] = "dev.duckcoder.egeondeck"
        let all = [raw(1, 0, "launchd"), raw(100, 1, "EgeonDeck"),
                   raw(200, 1, "com.docker.backend", docker),
                   raw(201, 200, "com.docker.build", docker),
                   raw(300, 1, "node", server)]
        XCTAssertEqual(ProcessTable.classify(all, app: 100, deck: "egeon").map(\.pid), [300])
    }

    func testLegacyTargetWithoutDeckStillCounts() {
        let all = [raw(1, 0, "launchd"), raw(100, 1, "EgeonDeck"),
                   raw(200, 1, "node", [ClaudeHooks.targetVariable: "velha/claude"])]
        let found = ProcessTable.classify(all, app: 100, deck: "egeon")
        XCTAssertEqual(found.map(\.node), ["velha/claude"])
        XCTAssertEqual(found.map(\.orphan), [true])
    }

    func testProcargsParsing() {
        var data = Data()
        var argc: Int32 = 2
        withUnsafeBytes(of: &argc) { data.append(contentsOf: $0) }
        data.append(contentsOf: Array("/usr/bin/node".utf8) + [0, 0, 0])
        data.append(contentsOf: Array("node".utf8) + [0] + Array("app.js".utf8) + [0])
        data.append(contentsOf: Array("EGEON_NODE=a/b".utf8) + [0] + Array("X=1=2".utf8) + [0] + [0])
        data.append(contentsOf: Array("ptr_munge=".utf8) + [0])
        let parsed = ProcessArguments(procargs: data)
        XCTAssertEqual(parsed?.arguments, ["node", "app.js"])
        XCTAssertEqual(parsed?.environment, ["EGEON_NODE": "a/b", "X": "1=2"])
        XCTAssertNil(ProcessArguments(procargs: Data([1])))
    }

    func testOrderAndAge() {
        let a = EgeonProcess(pid: 1, ppid: 0, started: t0, command: "", node: "b", orphan: false)
        let b = EgeonProcess(pid: 2, ppid: 0, started: t0.addingTimeInterval(5), command: "", node: "z", orphan: true)
        let c = EgeonProcess(pid: 3, ppid: 0, started: t0, command: "", node: "z", orphan: true)
        XCTAssertEqual(ProcessList.ordered([a, b, c]).map(\.pid), [3, 2, 1])
        XCTAssertEqual(ProcessList.age(42), "42 s")
        XCTAssertEqual(ProcessList.age(600), "10 min")
        XCTAssertEqual(ProcessList.age(3 * 3600 + 120), "3 h 2 min")
        XCTAssertEqual(ProcessList.age(19 * 86_400 + 16 * 3600), "19 d 16 h")
    }

    func testChildEnvironmentDropsInheritedMarks() {
        setenv(ProcessMark.node, "outro/terminal", 1)
        setenv(ClaudeHooks.targetVariable, "outro/terminal", 1)
        defer { unsetenv(ProcessMark.node); unsetenv(ClaudeHooks.targetVariable) }
        let env = AppEnvironment.forChildProcess()
        XCTAssertNil(env[ProcessMark.node])
        XCTAssertNil(env[ClaudeHooks.targetVariable])
    }

    func testCLIOffersPs() {
        XCTAssertTrue(EgeonCLI.body.contains("egeon ps [--orphans]"))
        XCTAssertTrue(EgeonCLI.body.contains("/processes/kill"))
    }

    func testDescendantsCrossProcessGroups() {
        let all = [raw(1, 0, "launchd"), raw(10, 1, "zsh"), raw(11, 10, "claude"),
                   raw(12, 11, "zsh"), raw(13, 12, "node"), raw(20, 1, "outro")]
        XCTAssertEqual(ProcessTable.descendants(of: 10, in: all).map(\.pid).sorted(), [11, 12, 13])
        XCTAssertEqual(ProcessTable.descendants(of: 13, in: all), [])
    }

    func testReapTakesOldOrphansButSparesTheClaudeDaemon() {
        let now = t0.addingTimeInterval(3 * 3600)
        func p(_ pid: Int32, _ ppid: Int32, _ command: String, age: TimeInterval, orphan: Bool = true) -> EgeonProcess {
            EgeonProcess(pid: pid, ppid: ppid, started: now.addingTimeInterval(-age), command: command,
                         node: "x/claude", orphan: orphan)
        }
        let list = [
            p(1, 1, "node server.js", age: 7200),
            p(2, 1, "node vite", age: 600),                     // novo demais
            p(3, 1, "/Users/a/.local/bin/claude daemon run --json-path x", age: 7200),
            p(4, 3, "claude bg-pty-host --bg-pty-host /tmp/s", age: 7200),
            p(5, 4, "npm exec @playwright/mcp@latest", age: 7200),  // debaixo do daemon
            p(6, 99, "claude --resume abc", age: 7200, orphan: false),
        ]
        XCTAssertEqual(ReapPolicy().victims(in: list, now: now).map(\.pid), [1])
        var policy = ReapPolicy()
        policy.minAgeMinutes = 5
        XCTAssertEqual(policy.victims(in: list, now: now).map(\.pid), [1, 2])
    }

    func testPolicyFileFillsMissingKeys() throws {
        let policy = try JSONDecoder().decode(ReapPolicy.self, from: Data(#"{"enabled":false}"#.utf8))
        XCTAssertFalse(policy.enabled)
        XCTAssertEqual(policy.intervalMinutes, 10)
        XCTAssertEqual(policy.minAgeMinutes, 60)
        let floor = try JSONDecoder().decode(ReapPolicy.self, from: Data(#"{"intervalMinutes":0}"#.utf8))
        XCTAssertEqual(floor.intervalMinutes, 1)
    }

    func testRelaunchLoopWithoutReadableMarkIsAdoptedByItsChildren() {
        let all = [
            raw(1, 0, "launchd"),
            raw(100, 1, "EgeonDeck"),
            // O laço: pai morto, ambiente ilegível; o filho renasce a cada queda.
            raw(200, 1, "bash", at: 0),
            raw(201, 200, "aws", at: 90_000, mark("3614/claude")),
            raw(202, 201, "session-manager-plugin", at: 90_001),
            // App solto no launchd com filho marcado não é adotado.
            RawProcess(pid: 300, ppid: 1, started: t0, name: "Docker",
                       command: "/Applications/Docker.app/Contents/MacOS/Docker"),
            raw(301, 300, "helper", mark("3614/claude")),
            // Pai sem marca que ainda tem pai vivo (um terminal seu) não é órfão.
            raw(400, 1, "Terminal", at: 0, ["__CFBundleIdentifier": "com.apple.Terminal"]),
            raw(401, 400, "zsh"),
            raw(402, 401, "node", mark("3614/claude")),
        ]
        let found = ProcessTable.classify(all, app: 100, deck: "egeon")
        let orphans = Set(found.filter(\.orphan).map(\.pid))
        XCTAssertTrue(orphans.isSuperset(of: [200, 201, 202]))
        XCTAssertFalse(orphans.contains(300))
        XCTAssertFalse(orphans.contains(400))
        XCTAssertFalse(orphans.contains(401))
        XCTAssertEqual(found.first { $0.pid == 200 }?.node, "3614/claude")

        // A idade é a da família: o filho de 10 minutos sai com o laço de um dia.
        let now = t0.addingTimeInterval(90_600)
        let victims = Set(ReapPolicy().victims(in: found, now: now).map(\.pid))
        XCTAssertTrue(victims.isSuperset(of: [200, 201, 202]))
    }
}
