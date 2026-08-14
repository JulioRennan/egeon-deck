import Foundation

/// Criação de worktrees do git, para abrir uma segunda frente do mesmo
/// repositório sem mexer no checkout onde você está.
enum Worktree {

    struct Status {
        let repoRoot: String
        let branch: String
        /// Mudanças em arquivos já rastreados.
        let hasDirtyTracked: Bool
        /// Arquivos novos, não rastreados e não ignorados.
        let untracked: [String]

        var isDirty: Bool { hasDirtyTracked || !untracked.isEmpty }
    }

    enum Failure: Error, CustomStringConvertible {
        case notARepo(String)
        case branchInUse(String, at: String)
        case destinationExists(String)
        case git(command: String, output: String)

        var description: String {
            switch self {
            case .notARepo(let path):
                return "\(path) não é um repositório git."
            case .branchInUse(let branch, let at):
                return "A branch \"\(branch)\" já está em uso na worktree \(at). "
                    + "O git não permite a mesma branch em dois lugares — escolha outro nome."
            case .destinationExists(let path):
                return "Já existe algo em \(path)."
            case .git(let command, let output):
                return "git \(command) falhou:\n\(output)"
            }
        }
    }

    // MARK: - Leitura

    static func status(of path: String) throws -> Status {
        let root = try run(["rev-parse", "--show-toplevel"], in: path).trimmed
        guard !root.isEmpty else { throw Failure.notARepo(path) }

        let branch = try run(["rev-parse", "--abbrev-ref", "HEAD"], in: path).trimmed

        let dirty = try run(["status", "--porcelain", "--untracked-files=no"], in: path)
        let untracked = try run(["ls-files", "--others", "--exclude-standard"], in: path)
            .split(whereSeparator: \.isNewline).map(String.init)

        return Status(repoRoot: root,
                      branch: branch,
                      hasDirtyTracked: !dirty.trimmed.isEmpty,
                      untracked: untracked)
    }

    /// Onde a worktree nasce: `<pai do repo>/.worktrees/<repo>/<branch>`.
    ///
    /// Fora do diretório de projetos para não misturar com repositórios de
    /// verdade, e fora do diretório do app porque worktree é artefato de git — se
    /// o app sumir, o trabalho não deve ficar órfão dentro da config dele.
    static func suggestedPath(repoRoot: String, branch: String) -> String {
        let repo = URL(fileURLWithPath: repoRoot)
        return repo.deletingLastPathComponent()
            .appendingPathComponent(".worktrees")
            .appendingPathComponent(repo.lastPathComponent)
            .appendingPathComponent(sanitize(branch))
            .path
    }

    /// `feature/PROJ-1234` viraria subdiretório; achatar deixa o caminho
    /// previsível e fácil de apagar.
    static func sanitize(_ branch: String) -> String {
        branch.replacingOccurrences(of: "/", with: "-")
    }

    /// Nome livre a partir do atual: `PROJ-1234` → `PROJ-1234-2`, `-3`…
    static func availableBranch(basedOn current: String, in path: String) -> String {
        let existing = (try? run(["branch", "--format=%(refname:short)", "--list"], in: path))?
            .split(whereSeparator: \.isNewline).map { String($0).trimmed } ?? []
        var n = 2
        while existing.contains("\(current)-\(n)") { n += 1 }
        return "\(current)-\(n)"
    }

    // MARK: - Criação

    struct Created {
        let path: String
        let branch: String
        /// Se as modificações em arquivos rastreados vieram junto, para relatar
        /// sem inventar.
        let carriedTrackedChanges: Bool
    }

    /// Cria a worktree em `destination`, numa branch nova apontando para o HEAD
    /// atual do repositório de origem.
    ///
    /// Branch nova, e não a mesma: o git recusa a mesma branch em duas
    /// worktrees, por design — dois checkouts movendo o mesmo ponteiro se
    /// atropelariam.
    static func create(from repoPath: String,
                       branch: String,
                       destination: String,
                       carryDirty: Bool) throws -> Created {
        let status = try status(of: repoPath)

        guard !FileManager.default.fileExists(atPath: destination) else {
            throw Failure.destinationExists(destination)
        }
        if let inUse = try worktreeUsing(branch: branch, in: repoPath) {
            throw Failure.branchInUse(branch, at: inUse)
        }

        // Feito ANTES de criar a worktree e sem tocar no working tree de origem:
        // `stash create` só escreve um objeto e devolve o sha. `stash push`
        // reverteria as mudanças do lado de cá, que não é o combinado.
        var stash = ""
        if carryDirty && status.hasDirtyTracked {
            stash = try run(["stash", "create"], in: repoPath).trimmed
        }

        try FileManager.default.createDirectory(
            atPath: (destination as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)

        _ = try run(["worktree", "add", "-b", branch, destination, "HEAD"], in: repoPath)

        if !stash.isEmpty {
            _ = try run(["stash", "apply", stash], in: destination)
        }

        Log.write("worktree: \(destination) criada na branch \(branch)"
                  + (stash.isEmpty ? "" : ", com as mudanças não commitadas"))

        return Created(path: destination,
                       branch: branch,
                       carriedTrackedChanges: !stash.isEmpty)
    }

    // MARK: - O que o git não versiona

    static let copyScriptURL = URL(fileURLWithPath:
        Flavor.current.config("worktree-copy.sh").path)

    /// Copia para a worktree tudo que o git não versiona: arquivos novos e
    /// também os ignorados — `.env`, `node_modules`, `.dart_tool`, `Pods`,
    /// `build`. Sem isso a worktree nasce sem configuração e sem dependências, e
    /// a "segunda frente" custa um `pub get` e um `pod install` antes de existir.
    ///
    /// Fica num script à parte, e não embutido no app, porque é o passo que cada
    /// projeto quer ajustar — e porque uma cópia de gigabytes tem que ser
    /// legível e editável por quem espera por ela.
    static func installCopyScript() {
        // Reescrever por cima apagaria ajustes do usuário.
        guard !FileManager.default.fileExists(atPath: copyScriptURL.path) else { return }

        let script = """
        #!/usr/bin/env bash
        # Egeon Deck — leva para a worktree nova tudo que o git não versiona.
        #
        # `git ls-files --others --directory` (sem --exclude-standard) lista de uma
        # vez os arquivos novos E os ignorados, e `--directory` devolve
        # `node_modules/` como uma entrada em vez de cem mil.
        #
        # `cp -c` usa clonefile do APFS: a cópia é instantânea e não ocupa disco
        # até que um dos lados escreva. É o que torna copiar node_modules viável.
        # Fora de APFS o clone falha e a cópia comum assume.
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

        try? FileManager.default.createDirectory(
            at: copyScriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? script.write(to: copyScriptURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: copyScriptURL.path)
        Log.write("worktree: script de cópia escrito em \(copyScriptURL.path)")
    }

    /// Roda o script fora da main thread: com node_modules grande e sem APFS,
    /// isso é minutos, e travar a UI seria inaceitável.
    static func copyUnversioned(from source: String, to destination: String,
                                completion: @escaping (String) -> Void) {
        installCopyScript()

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [copyScriptURL.path, source, destination]
            task.environment = AppEnvironment.forChildProcess()

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
            } catch {
                DispatchQueue.main.async { completion("erro ao rodar o script: \(error)") }
                return
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let output = (String(data: data, encoding: .utf8) ?? "").trimmed

            Log.write("worktree: cópia de arquivos não versionados terminou\n\(output)")
            DispatchQueue.main.async {
                completion(output.split(whereSeparator: \.isNewline).last.map(String.init)
                           ?? "cópia concluída")
            }
        }
    }

    /// Qual worktree já usa essa branch, se alguma. Antecipa o `fatal:` do git
    /// com uma mensagem que diz o que fazer.
    private static func worktreeUsing(branch: String, in path: String) throws -> String? {
        let listing = try run(["worktree", "list", "--porcelain"], in: path)
        var current: String?
        for line in listing.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("worktree ") {
                current = String(line.dropFirst("worktree ".count))
            } else if line == "branch refs/heads/\(branch)" {
                return current
            }
        }
        return nil
    }

    // MARK: - Remoção

    /// Se este caminho é uma worktree ligada, e não o checkout principal.
    ///
    /// Numa worktree ligada o `--git-dir` aponta para
    /// `<principal>/.git/worktrees/<nome>`, enquanto o `--git-common-dir` continua
    /// sendo `<principal>/.git`. No checkout principal os dois coincidem — é essa
    /// diferença que impede oferecer "apagar a worktree" para o repositório de
    /// verdade.
    static func isLinkedWorktree(_ path: String) -> Bool {
        guard let gitDir = try? run(["rev-parse", "--absolute-git-dir"], in: path).trimmed,
              let commonDir = try? run(["rev-parse", "--path-format=absolute",
                                        "--git-common-dir"], in: path).trimmed
        else { return false }
        return gitDir != commonDir
    }

    /// Caminho do repositório principal. `worktree remove` não roda de dentro da
    /// worktree que está sendo removida.
    ///
    /// A primeira entrada de `worktree list` é sempre a principal — é a única
    /// forma que vale para os dois layouts. Derivar do `--git-common-dir`
    /// cortando o último componente parece funcionar, mas só num clone comum,
    /// onde o common-dir é `<repo>/.git`. Num repositório bare o common-dir É o
    /// próprio repositório (`<repo>.git`), e cortar dali aponta para a pasta que
    /// o contém — que não é git nenhum, e o comando morre com
    /// "fatal: not a git repository".
    static func mainWorktree(of path: String) -> String? {
        guard let listing = try? run(["worktree", "list", "--porcelain"], in: path) else {
            return nil
        }
        for line in listing.split(whereSeparator: \.isNewline) where line.hasPrefix("worktree ") {
            return String(line.dropFirst("worktree ".count))
        }
        return nil
    }

    struct Losses {
        let modified: [String]
        let untracked: [String]
        let unpushedCommits: Int

        var isEmpty: Bool { modified.isEmpty && untracked.isEmpty && unpushedCommits == 0 }
    }

    /// O que desaparece se esta worktree for apagada.
    ///
    /// Commits sem upstream contam: eles vivem na branch, que sobrevive à
    /// remoção — mas se ninguém souber que existem, ninguém vai buscá-los.
    static func losses(in path: String) throws -> Losses {
        let modified = try run(["status", "--porcelain", "--untracked-files=no"], in: path)
            .split(whereSeparator: \.isNewline)
            .map { String($0.dropFirst(3)) }
        let untracked = try run(["ls-files", "--others", "--exclude-standard"], in: path)
            .split(whereSeparator: \.isNewline).map(String.init)

        // Sem upstream, `@{u}` falha — e aí "não enviado" não é medível, então 0.
        let ahead = (try? run(["rev-list", "--count", "@{u}..HEAD"], in: path).trimmed) ?? "0"

        return Losses(modified: modified,
                      untracked: untracked,
                      unpushedCommits: Int(ahead) ?? 0)
    }

    /// Apaga a worktree do disco e limpa o registro do git.
    ///
    /// `--force` é necessário na prática: a worktree nasce com as mudanças não
    /// commitadas e com os arquivos ignorados copiados, e o git recusa remover
    /// uma árvore suja sem ele. Quem chama tem de ter mostrado as perdas antes.
    static func remove(_ path: String) throws {
        guard let main = mainWorktree(of: path) else {
            throw Failure.notARepo(path)
        }
        _ = try run(["worktree", "remove", "--force", path], in: main)
        // Registro órfão sobra quando a pasta já tinha sido apagada à mão.
        _ = try? run(["worktree", "prune"], in: main)
        Log.write("worktree: \(path) removida do disco")
    }

    /// A branch continua existindo depois de remover a worktree — o trabalho
    /// commitado não se perde. Apagar é decisão separada.
    static func branchOf(_ path: String) -> String? {
        try? run(["rev-parse", "--abbrev-ref", "HEAD"], in: path).trimmed
    }

    // MARK: - git

    @discardableResult
    private static func run(_ arguments: [String], in directory: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git"] + arguments
        task.currentDirectoryURL = URL(fileURLWithPath: directory)
        task.environment = AppEnvironment.forChildProcess()

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        guard task.terminationStatus == 0 else {
            throw Failure.git(command: arguments.joined(separator: " "), output: output.trimmed)
        }
        return output
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
