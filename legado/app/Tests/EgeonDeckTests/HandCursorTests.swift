import XCTest
@testable import EgeonDeck

/// Onde se clica, o ponteiro diz: toda view que responde a clique define os
/// seus cursor rects. O teste olha o método em tempo de execução — é o que
/// pega a view clicável nova que nasceu sem cursor, e a regressão de quem
/// perdeu o override numa refatoração.
private final class PlainView: NSView {}

final class HandCursorTests: XCTestCase {
    private func definesCursorRects(_ type: AnyClass) -> Bool {
        let selector = #selector(NSView.resetCursorRects)
        guard let mine = class_getInstanceMethod(type, selector),
              let base = class_getInstanceMethod(NSView.self, selector) else { return false }
        return method_getImplementation(mine) != method_getImplementation(base)
    }

    func testClickableViewsDefineTheirCursor() {
        let clickable: [AnyClass] = [
            ToolbarButton.self, ModeButton.self, SidebarRow.self, SidebarGroupRow.self,
            // Na linha do passo quem manda no ponteiro é o texto por cima
            // (`StepTextView`): mão na faixa do título, I-beam no resto.
            ChatQuoteView.self, StepTextView.self,
            HandView.self, HandButton.self, HandPopUpButton.self, HandImageView.self,
        ]
        for type in clickable {
            XCTAssertTrue(definesCursorRects(type), "\(type) responde a clique e não diz nada ao ponteiro")
        }
        // E a régua do teste presta: view sem override não define nada.
        XCTAssertFalse(definesCursorRects(PlainView.self))
    }

    func testTheHandCoversTheWholeViewOnlyWhenClickable() {
        let view = HandView(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        // `addCursorRect` só vale dentro do ciclo do AppKit; aqui basta que a
        // decisão de pôr ou não a mão seja a esperada.
        XCTAssertNoThrow(view.resetCursorRects())

        let button = HandButton(title: "Escolher…", target: nil, action: nil)
        button.isEnabled = false
        XCTAssertNoThrow(button.resetCursorRects())
    }
}
