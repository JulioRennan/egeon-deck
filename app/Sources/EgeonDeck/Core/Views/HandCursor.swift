import AppKit

// MARK: - Onde se clica, o ponteiro diz

/// O padrão do macOS é seta até em cima de botão; aqui a escolha é a **mão em
/// tudo que responde a clique**, como na web. Num app que é quase todo view
/// desenhada à mão — pastilha, aba, linha da barra, título de passo — a seta
/// não distingue o que age do que só está escrito.
///
/// Cursor **rect**, e não `cursorUpdate`: é assim que o AppKit (e o
/// `NSTextView`, que põe o I-beam) resolve o ponteiro; sobrescrever
/// `cursorUpdate` numa view que tem cursor rect por baixo não é chamado.
enum HandCursor {
    /// Chame do `resetCursorRects` da view. `when` desliga a mão para o estado
    /// em que ela não é clicável (linha morta, item que não abre).
    static func fill(_ view: NSView, when clickable: Bool = true) {
        guard clickable else { return }
        view.addCursorRect(view.bounds, cursor: .pointingHand)
    }
}

/// View crua que é clicável — a linha de um popup, uma citação. `NSView` não
/// tem cursor; esta tem.
class HandView: NSView {
    override func resetCursorRects() { HandCursor.fill(self) }
}

/// Imagem clicável — o botão de enviar do composer.
final class HandImageView: NSImageView {
    override func resetCursorRects() { HandCursor.fill(self) }
}

/// Botão e pull-down com a mão — o AppKit não dá cursor nenhum a eles.
/// Desabilitado volta à seta: ali o clique não faz nada mesmo.
final class HandButton: NSButton {
    override func resetCursorRects() { HandCursor.fill(self, when: isEnabled) }
}

final class HandPopUpButton: NSPopUpButton {
    override func resetCursorRects() { HandCursor.fill(self, when: isEnabled) }
}
