import Darwin
import Foundation

/// Leva para a worktree nova o que o git não versiona, clonando cada entrada
/// inteira de uma vez.
///
/// O `cp -Rc` do script clona ARQUIVO por arquivo: um `node_modules` de 54 mil
/// itens levava 7,5 s. `clonefile` numa pasta clona a árvore toda numa chamada
/// só do APFS — 1,4 s para o mesmo `node_modules`, e sem ocupar disco até um
/// dos lados escrever. `ditto --clone` e `FileManager.copyItem` também vão
/// arquivo por arquivo (8,7 s e 6,9 s), por isso a chamada é direta.
enum UnversionedCopy {
    struct Outcome: Equatable {
        var copied: Int
        var failed: [String]
    }

    /// O que `git ls-files --others --directory` devolve: os arquivos novos E os
    /// ignorados, com `node_modules/` como uma entrada só. `.git` nunca.
    static func entries(in source: String) -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["ls-files", "--others", "--directory", "-z"]
        task.currentDirectoryURL = URL(fileURLWithPath: source)
        task.environment = AppEnvironment.forChildProcess()
        // Para arquivo, e não Pipe: o fd de escrita de um Pipe é herdado por quem
        // for lançado depois e prende a leitura (ADR-017).
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("egeon-ls-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: out) }
        guard let handle = try? FileHandle(forWritingTo: out) else { return [] }
        task.standardOutput = handle
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        task.waitUntilExit()
        try? handle.close()
        let data = (try? Data(contentsOf: out)) ?? Data()
        return data.split(separator: 0).compactMap { String(data: Data($0), encoding: .utf8) }
            .filter { $0 != ".git" && $0 != ".git/" }
    }

    /// Clona cada entrada para o mesmo caminho dentro de `destination`. Em
    /// paralelo: `clonefile` é metadado, e uma pasta `__pycache__` por vez
    /// era tempo de fila, não de disco.
    static func copy(_ entries: [String], from source: String, to destination: String) -> Outcome {
        let lock = NSLock()
        var outcome = Outcome(copied: 0, failed: [])
        DispatchQueue.concurrentPerform(iterations: entries.count) { i in
            let item = entries[i]
            let relative = item.hasSuffix("/") ? String(item.dropLast()) : item
            let from = (source as NSString).appendingPathComponent(relative)
            let to = (destination as NSString).appendingPathComponent(relative)
            let ok = clone(from, to)
            lock.lock()
            if ok { outcome.copied += 1 } else { outcome.failed.append(item) }
            lock.unlock()
        }
        outcome.failed.sort()
        return outcome
    }

    /// Clone do APFS, e cópia comum quando ele não dá — outro volume, outro
    /// sistema de arquivos. O que já existe no destino fica: a worktree pode
    /// ter sido reaproveitada com coisa sua dentro.
    static func clone(_ from: String, _ to: String) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: to) { return true }
        try? fm.createDirectory(atPath: (to as NSString).deletingLastPathComponent,
                                withIntermediateDirectories: true)
        if clonefile(from, to, UInt32(CLONE_NOFOLLOW)) == 0 { return true }
        return (try? fm.copyItem(atPath: from, toPath: to)) != nil
    }

    /// O script ainda é o que o app escreveu, só com outro cabeçalho? Aí a
    /// cópia rápida faz o mesmo que ele. Mexeu na lógica — pulou uma pasta,
    /// rodou um `npm ci` —, vale o script, que é para isso que ele existe.
    static func isStockScript(_ text: String) -> Bool {
        body(text) == body(stockScriptBody)
    }

    private static func body(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// O corpo do script que o app escreve (sem comentários, que não contam).
    static let stockScriptBody = """
    set -uo pipefail
    SRC="${1:?uso: worktree-copy.sh <origem> <destino>}"
    DST="${2:?uso: worktree-copy.sh <origem> <destino>}"
    cd "$SRC" || exit 1
    copiados=0
    while IFS= read -r -d '' item; do
      case "$item" in
        .git/|.git) continue ;;
      esac
      destino="$DST/$item"
      mkdir -p "$(dirname "${destino%/}")"
      if cp -Rc "$SRC/$item" "${destino%/}" 2>/dev/null \\
         || cp -R "$SRC/$item" "${destino%/}" 2>/dev/null; then
        copiados=$((copiados + 1))
        echo "  $item"
      else
        echo "  FALHOU: $item" >&2
      fi
    done < <(git ls-files --others --directory -z)
    echo "$copiados entrada(s) copiada(s) de $SRC para $DST"
    """
}
