import XCTest
@testable import EgeonDeck

final class AppClaimsTests: XCTestCase {
    func testAppWithoutMarkIsNeverClosed() {
        // Aberto por você: nenhum terminal do Egeon é o dono dele.
        var claims = AppClaims()
        XCTAssertEqual(claims.release(["a/claude"], live: [], launchers: [:]), [])
    }

    func testOpenerLeavingClosesTheApp() {
        var claims = AppClaims()
        let launchers = ["com.docker.docker": "a/back"]
        XCTAssertEqual(claims.release(["outra/x"], live: ["a/back"], launchers: launchers), [])
        XCTAssertEqual(claims.release(["a/back"], live: ["b/y"], launchers: launchers), ["com.docker.docker"])
    }

    func testHeirIsTheLastUser() {
        // Quem abriu saiu, mas `b/back` ainda usava: ficou como herdeiro.
        var claims = AppClaims(apps: ["com.docker.docker": .init(launched: true, users: ["b/back"])])
        let launchers = ["com.docker.docker": "a/back"]
        XCTAssertEqual(claims.release(["c/z"], live: ["b/back"], launchers: launchers), [])
        XCTAssertEqual(claims.release(["b/back"], live: [], launchers: launchers), ["com.docker.docker"])
        XCTAssertNil(claims.apps["com.docker.docker"])
    }

    func testDeadHeirDoesNotHoldTheApp() {
        var claims = AppClaims(apps: ["com.docker.docker": .init(launched: true, users: ["a/back", "velha/x"])])
        XCTAssertEqual(claims.release(["a/back"], live: ["c/y"], launchers: [:]), ["com.docker.docker"])
    }

    func testOpenerIsOnlyTheAppTheLaunchdOpened() {
        let engine = ["__CFBundleIdentifier": "com.docker.docker", "EGEON_NODE": "a/back"]
        XCTAssertEqual(AppClaims.opener(of: "com.docker.docker", environment: engine), "a/back")
        // A janela do Docker Desktop: outro bundle, com o ambiente do motor.
        XCTAssertNil(AppClaims.opener(of: "com.electron.dockerdesktop", environment: engine))
        XCTAssertNil(AppClaims.opener(of: "com.google.Chrome",
                                      environment: ["__CFBundleIdentifier": "com.google.Chrome"]))
    }

    func testContainerOwners() {
        let paths = ["main": ["/w/proj"], "feat": ["/w/proj/worktrees/feat"], "solta": ["/w/outra", "/w/wt/x"]]
        let owners = ContainerOwners(workingDirs: ["/w/proj/api", "/w/proj/worktrees/feat", "/w/wt/x/db"],
                                     paths: paths)
        XCTAssertEqual(owners.benches, ["main", "feat", "solta"])
        XCTAssertFalse(owners.unknown)
        // Sem rótulo de compose, ou de pasta de bancada nenhuma.
        XCTAssertTrue(ContainerOwners(workingDirs: [""], paths: paths).unknown)
        XCTAssertTrue(ContainerOwners(workingDirs: ["/w/projeto"], paths: paths).unknown)
        XCTAssertEqual(ContainerOwners(workingDirs: [], paths: paths), ContainerOwners(workingDirs: [], paths: [:]))
    }

    func testSocketPeers() {
        let lsof = """
        p10
        f3
        d0xaaa
        n/tmp/s.sock
        f4
        d0xbbb
        n->0xccc
        p20
        f5
        d0xccc
        n/tmp/s.sock
        p30
        f3
        d0xddd
        n->0xeee
        """
        let table = SocketTable(lsof: lsof)
        XCTAssertEqual(table.connected([10, 30], to: [20]), [10])
        XCTAssertEqual(table.connected([30], to: [20]), [])
    }
}
