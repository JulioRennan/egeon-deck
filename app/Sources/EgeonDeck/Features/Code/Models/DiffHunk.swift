import Foundation

// MARK: - Diff como dados, para a bolha desenhar lado a lado

/// Uma linha do diff unificado que o passo guarda (`ChatStep.diff`).
struct DiffLine: Equatable {
    enum Kind: Equatable { case context, added, removed, note }
    let kind: Kind
    let text: String
}

/// Um trecho do diff, com onde ele começa em cada versão — vem do
/// `structuredPatch` do CLI (`@@ -a,b +c,d @@`). Sem cabeçalho (o diff
/// montado ao vivo de `old_string`/`new_string`) os números ficam vazios.
struct DiffHunk: Equatable {
    var oldStart: Int?
    var newStart: Int?
    var lines: [DiffLine] = []

    /// As linhas do passo (` `, `-`, `+`, `@@`, `…`) em trechos.
    static func parse(_ raw: [String]) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var current = DiffHunk()
        var started = false
        for line in raw {
            if line.hasPrefix("@@") {
                if started { hunks.append(current) }
                current = DiffHunk(oldStart: number(after: "-", in: line),
                                   newStart: number(after: "+", in: line))
                started = true
                continue
            }
            started = true
            switch line.first {
            case "+": current.lines.append(DiffLine(kind: .added, text: String(line.dropFirst())))
            case "-": current.lines.append(DiffLine(kind: .removed, text: String(line.dropFirst())))
            case "…": current.lines.append(DiffLine(kind: .note, text: line))
            case " ": current.lines.append(DiffLine(kind: .context, text: String(line.dropFirst())))
            default:  current.lines.append(DiffLine(kind: .context, text: line))
            }
        }
        if started { hunks.append(current) }
        return hunks
    }

    private static func number(after sign: Character, in header: String) -> Int? {
        guard let signIndex = header.firstIndex(of: sign) else { return nil }
        let digits = header[header.index(after: signIndex)...].prefix { $0.isNumber }
        return Int(digits)
    }

    /// Cabeçalho unificado, para o parser gravar o que o `structuredPatch` diz.
    static func header(oldStart: Int, oldLines: Int, newStart: Int, newLines: Int) -> String {
        "@@ -\(oldStart),\(oldLines) +\(newStart),\(newLines) @@"
    }

    /// Uma célula de um lado do diff lado a lado.
    struct Cell: Equatable {
        let number: Int?
        let kind: DiffLine.Kind
        let text: String
    }

    /// Uma linha da vista lado a lado: esquerda é o antes, direita o depois.
    /// Lado vazio é a linha que só existe do outro lado.
    struct Row: Equatable {
        let left: Cell?
        let right: Cell?
    }

    /// Pareia como o GitHub: contexto ocupa os dois lados; um bloco de `-`
    /// seguido de um bloco de `+` alinha linha a linha, e o que sobra fica
    /// sozinho no seu lado. Os números seguem cada versão.
    var rows: [Row] {
        var out: [Row] = []
        var oldNumber = oldStart
        var newNumber = newStart
        var removed: [DiffLine] = []
        var added: [DiffLine] = []

        func flush() {
            for i in 0..<max(removed.count, added.count) {
                var left: Cell?
                var right: Cell?
                if i < removed.count {
                    left = Cell(number: oldNumber, kind: .removed, text: removed[i].text)
                    oldNumber = oldNumber.map { $0 + 1 }
                }
                if i < added.count {
                    right = Cell(number: newNumber, kind: .added, text: added[i].text)
                    newNumber = newNumber.map { $0 + 1 }
                }
                out.append(Row(left: left, right: right))
            }
            removed = []
            added = []
        }

        for line in lines {
            switch line.kind {
            case .removed:
                // `+` já acumulado e chega outro `-`: é outro bloco.
                if !added.isEmpty { flush() }
                removed.append(line)
            case .added:
                added.append(line)
            case .context:
                flush()
                out.append(Row(left: Cell(number: oldNumber, kind: .context, text: line.text),
                               right: Cell(number: newNumber, kind: .context, text: line.text)))
                oldNumber = oldNumber.map { $0 + 1 }
                newNumber = newNumber.map { $0 + 1 }
            case .note:
                flush()
                let note = Cell(number: nil, kind: .note, text: line.text)
                out.append(Row(left: note, right: note))
            }
        }
        flush()
        return out
    }
}
