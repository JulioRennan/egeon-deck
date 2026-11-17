import Foundation

/// De quais bancadas são os containers rodando no Docker (ADR-084), pelo rótulo
/// `com.docker.compose.project.working_dir` — a pasta de onde o compose subiu.
/// Container não segura conexão com ninguém: `up -d` e o terminal está livre,
/// mas fechar o Docker ainda derruba o banco da bancada ao lado.
struct ContainerOwners: Equatable {
    var benches: Set<String> = []
    /// Container sem rótulo, ou de pasta que não é de bancada nenhuma: não dá
    /// para dizer de quem é, então segura o Docker aberto.
    var unknown = false

    /// `workingDirs`: uma linha por container. `paths`: bancada → pastas (a
    /// dela e a de cada nó em worktree própria), já expandidas. A pasta mais
    /// funda ganha: worktree pode morar dentro da pasta de outra bancada.
    init(workingDirs: [String], paths: [String: [String]]) {
        let pairs = paths.flatMap { bench, dirs in dirs.map { (bench, $0) } }
        for dir in workingDirs.map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let owner = pairs
                .filter { dir == $0.1 || dir.hasPrefix($0.1.hasSuffix("/") ? $0.1 : $0.1 + "/") }
                .max { $0.1.count < $1.1.count }?.0
            if let owner { benches.insert(owner) } else { unknown = true }
        }
    }
}
