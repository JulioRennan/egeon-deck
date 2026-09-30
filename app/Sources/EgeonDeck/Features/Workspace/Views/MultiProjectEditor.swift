import AppKit

/// Nome e pastas de um multi-projeto — o diálogo que abre de dentro do
/// formulário do workspace.
///
/// As opções são só as pastas do workspace: multi-projeto junta projetos que já
/// são deste assunto, e o multi-projeto aponta para projetos por id. Pasta nova
/// entra antes, em "Adicionar pastas…".
final class MultiProjectEditor: NSObject {
    private var folders: [String]
    private var boxes: [NSButton] = []
    private let list = FlippedView()
    private let scroll = NSScrollView()
    private let width: CGFloat = 320
    private let row: CGFloat = 20

    private init(folders: [String]) {
        self.folders = folders
    }

    static func ask(_ draft: MultiProjectDraft, folders: [String]) -> MultiProjectDraft? {
        MultiProjectEditor(folders: folders).run(draft)
    }

    private func run(_ draft: MultiProjectDraft) -> MultiProjectDraft? {
        let alert = NSAlert()
        alert.messageText = draft.id == nil && draft.name.isEmpty ? "Novo multi-projeto" : "Editar multi-projeto"
        alert.informativeText = "Marque as pastas que a bancada vai ver juntas, cada uma numa subpasta."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancelar")

        let listHeight: CGFloat = 180
        guard !folders.isEmpty || !draft.folders.isEmpty else {
            alert.informativeText = "Adicione antes as pastas do workspace — o multi-projeto junta algumas delas."
            alert.buttons.first?.title = "Entendi"
            alert.buttons.last?.isHidden = true
            alert.runModal()
            return nil
        }

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: listHeight + 34))

        let nameField = NSTextField(frame: NSRect(x: 0, y: listHeight + 10, width: width, height: 24))
        nameField.stringValue = draft.name
        nameField.placeholderString = "nome do multi-projeto"
        container.addSubview(nameField)

        scroll.frame = NSRect(x: 0, y: 0, width: width, height: listHeight)
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        container.addSubview(scroll)

        let chosen = Set(draft.folders.map(ProjectConfig.normalize))
        // Pasta do rascunho que o workspace não tem mais — tirada lá em cima e
        // escolhida aqui antes — não some da lista sem você ver.
        for folder in draft.folders where !contains(folder) { folders.append(folder) }
        for folder in folders { addBox(folder, on: chosen.contains(ProjectConfig.normalize(folder))) }

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        var result = draft
        result.folders = zip(folders, boxes).filter { $0.1.state == .on }.map(\.0)
        let typed = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        result.name = typed.isEmpty ? result.summary : typed
        guard !result.folders.isEmpty else { return nil }
        return result
    }

    private func contains(_ folder: String) -> Bool {
        folders.contains { ProjectConfig.normalize($0) == ProjectConfig.normalize(folder) }
    }

    private func addBox(_ folder: String, on: Bool) {
        let box = HandButton(checkboxWithTitle: (ProjectConfig.normalize(folder) as NSString)
            .abbreviatingWithTildeInPath, target: nil, action: nil)
        box.state = on ? .on : .off
        box.lineBreakMode = .byTruncatingMiddle
        boxes.append(box)
        list.addSubview(box)
        layoutList()
    }

    private func layoutList() {
        let inner = scroll.contentSize.width
        list.frame = NSRect(x: 0, y: 0, width: inner,
                            height: max(CGFloat(boxes.count) * row + 4, scroll.contentSize.height))
        for (i, box) in boxes.enumerated() {
            box.frame = NSRect(x: 6, y: 2 + CGFloat(i) * row, width: inner - 12, height: 18)
        }
    }
}

/// Lista de cima para baixo, como se lê.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
