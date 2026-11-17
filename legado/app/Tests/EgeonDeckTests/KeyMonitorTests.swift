import AppKit
import XCTest
@testable import EgeonDeck

/// Tecla com o terminal focado é você falando com o agente — menos o atalho do
/// app, que nunca chega ao pty. Contar o ⌘1 da troca de aba como digitação
/// apagava a ampulheta de quem estava na frente (ADR-063).
final class KeyMonitorTests: XCTestCase {
    func testPlainKeysReachThePty() {
        XCTAssertTrue(Dispatcher.reachesPty([], "a"))
        XCTAssertTrue(Dispatcher.reachesPty(.control, "c"), "⌃C interrompe o agente")
        XCTAssertTrue(Dispatcher.reachesPty(.shift, "A"))
    }

    func testTabShortcutsDoNotCountAsTyping() {
        XCTAssertFalse(Dispatcher.reachesPty(.command, "1"))
        XCTAssertFalse(Dispatcher.reachesPty(.command, "]"))
        XCTAssertFalse(Dispatcher.reachesPty([.command, .shift], "}"))
        XCTAssertFalse(Dispatcher.reachesPty(.command, "w"))
    }

    func testPasteStillCounts() {
        XCTAssertTrue(Dispatcher.reachesPty(.command, "v"))
    }
}
