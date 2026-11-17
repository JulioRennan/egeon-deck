import Foundation

// MARK: - Remover a bancada

/// A parte da remoção que mexe em disco: apagar as worktrees, uma a uma.
///
/// Roda FORA da main thread. `worktree remove --force` numa árvore com
/// `node_modules` leva segundos — às vezes minutos —, e na main isso era o app
/// inteiro congelado com a bancada ainda na tela, sem dizer nada. Sem estado
/// próprio: quem apaga entra por closure, como no `WorkbenchCleaner`, e é o
/// que deixa a contagem de falhas e sobras testável sem git.
enum WorkbenchRemoval {
    struct Target {
        let path: String
        /// Como a worktree aparece no alerta e no log: `repo · branch`.
        let label: String
    }

    struct Outcome {
        var removed: [Target] = []
        /// Pastas que o git já desregistrou mas não terminou de apagar — a
        /// faxina delas vem depois que os processos da bancada morrerem (ADR-060).
        var leftovers: [String] = []
        var failures: [(target: Target, error: Error)] = []

        var succeeded: Bool { failures.isEmpty }
    }

    static func purge(_ targets: [Target],
                      remove: (String) throws -> Void = Worktree.remove) -> Outcome {
        var outcome = Outcome()
        for target in targets {
            do {
                try remove(target.path)
                outcome.removed.append(target)
            } catch Worktree.Failure.leftovers(let path, let reason) {
                // O registro já foi: a worktree acabou, o que sobrou é pasta. Segurar
                // a bancada por causa dela seria segurar por um problema que a
                // própria remoção resolve — quem escreve lá dentro são os processos
                // DESTA bancada, e eles morrem junto com ela.
                Log.write("worktree: \(path) — \(reason); a pasta fica para a faxina "
                          + "depois que os processos da bancada morrerem")
                outcome.removed.append(target)
                outcome.leftovers.append(path)
            } catch {
                // No log também: o alerta some com um OK, e é a mensagem do git que
                // diz por que a pasta resistiu.
                Log.write("worktree: falha ao apagar \(target.path) — \(error)")
                outcome.failures.append((target, error))
            }
        }
        return outcome
    }

    /// A segunda passada nas sobras, já com os processos da bancada mortos.
    /// Também fora da main: `finishRemoval` insiste com `Thread.sleep`.
    static func sweep(_ paths: [String]) {
        for path in paths {
            do {
                try Worktree.finishRemoval(of: path, registered: false)
                Log.write("worktree: \(path) apagada na segunda passada")
            } catch {
                Log.write("worktree: \(path) resistiu — \(error)")
            }
        }
    }

    /// A fila da remoção. Serial: duas bancadas removidas em seguida que
    /// dividem repositório disputariam o `.git/worktrees` do mesmo checkout.
    static let queue = DispatchQueue(label: "egeon.workbench-removal", qos: .userInitiated)
}
