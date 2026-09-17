import AppKit

// MARK: - Clique ou arrasto?

/// O laço que separa as duas coisas que um `mouseDown` pode ser: soltou parado é
/// clique, andou mais que o limiar é arrasto.
///
/// Genérico porque a barra lateral e a faixa de abas precisam exatamente do
/// mesmo laço com cargas diferentes (um item da árvore, um id de bancada) — e
/// porque o limiar é a defesa contra a mão trêmula: sem ele, escolher uma
/// bancada com o dedo pesado a mudava de lugar.
///
/// `window.nextEvent` de propósito: enquanto o botão está apertado, esta view
/// drena os eventos de mouse da janela e ninguém mais precisa saber que existe
/// um arrasto em curso.
enum PressDrag {
    enum Phase { case began, moved, ended, cancelled }

    struct Step<Payload> {
        let phase: Phase
        let payload: Payload
        /// Onde o mouse está, em coordenadas da janela.
        let point: NSPoint
        /// Onde o arrasto começou, em coordenadas da janela.
        let origin: NSPoint
    }

    static let threshold: CGFloat = 4

    static func track<Payload>(_ event: NSEvent, in view: NSView, payload: Payload,
                               drag: ((Step<Payload>) -> Void)?,
                               click: @escaping () -> Void) {
        let start = event.locationInWindow
        var dragging = false
        guard let window = view.window else { return click() }

        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = next.locationInWindow
            if next.type == .leftMouseUp {
                if dragging {
                    drag?(Step(phase: .ended, payload: payload, point: point, origin: start))
                } else {
                    click()
                }
                return
            }
            if !dragging {
                guard hypot(point.x - start.x, point.y - start.y) > threshold, drag != nil
                else { continue }
                dragging = true
                drag?(Step(phase: .began, payload: payload, point: point, origin: start))
            }
            drag?(Step(phase: .moved, payload: payload, point: point, origin: start))
        }
        if dragging {
            drag?(Step(phase: .cancelled, payload: payload, point: start, origin: start))
        }
    }
}
