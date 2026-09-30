import Foundation

/// O que o campo de pasta do terminal oferece: as subpastas da bancada que são
/// repositório — em multi-projeto, um repo por subpasta —, sempre relativas.
///
/// Só de dentro. Relativo é o que vale em qualquer checkout: na worktree, cada
/// subpasta é a worktree daquele repo. Oferecer o checkout principal de outro
/// projeto na lista seria convidar o terminal a trabalhar fora da branch da
/// bancada; quem precisa disso digita ou usa o "Escolher…" (ADR-017/065).
enum FolderSuggestions {
    static func list(repoChildren: [String]) -> [String] {
        repoChildren.sorted()
    }

    /// Subpastas da raiz que são repositório — pasta com `.git` (checkout ou
    /// worktree) ou link para uma.
    static func repoChildren(of root: URL) -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { entry in
            guard !entry.hasPrefix(".") else { return false }
            return fm.fileExists(atPath: root.appendingPathComponent(entry).appendingPathComponent(".git").path)
        }
    }
}
