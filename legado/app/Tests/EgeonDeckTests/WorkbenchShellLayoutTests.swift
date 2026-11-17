import XCTest
@testable import EgeonDeck

/// A barra de cima é a faixa da titlebar: tem de correr de borda a borda em
/// todo modo, para arrasto e duplo clique funcionarem em qualquer ponto dela.
/// Quem cede à barra lateral é só o conteúdo.
@MainActor
final class WorkbenchShellLayoutTests: XCTestCase {
    private func shell(mode: ViewMode, inset: CGFloat) -> WorkbenchShell {
        let shell = WorkbenchShell(frame: NSRect(x: 0, y: 0, width: 1000, height: 700), mode: mode)
        shell.contentInset = inset
        shell.layoutSubtreeIfNeeded()
        return shell
    }

    func testBarSpansFullWidthInEveryMode() {
        for mode in ViewMode.all {
            let s = shell(mode: mode, inset: 280)
            XCTAssertEqual(s.barFrame, NSRect(x: 0, y: 0, width: 1000, height: ViewToolbar.height),
                           "modo \(mode.rawValue)")
        }
    }

    func testOnlyContentYieldsToSidebar() {
        let s = shell(mode: .chat, inset: 280)
        XCTAssertEqual(s.contentFrame.minX, 280)
        XCTAssertEqual(s.contentFrame.width, 720)
        XCTAssertEqual(s.contentFrame.minY, ViewToolbar.height)
        XCTAssertEqual(s.visibleContent.frame, s.contentFrame)

        let canvas = shell(mode: .canvas, inset: 0)
        XCTAssertEqual(canvas.contentFrame.minX, 0)
        XCTAssertEqual(canvas.contentFrame.width, 1000)
    }
}
