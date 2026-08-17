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
        case destinationExists(String)
        case git(command: String, output: String)

        var description: String {
            switch self {
            case .notARepo(let path):
                return "\(path) não é um repositório git."
            case .destinationExists(let path):
                return "Já existe algo em \(path) — apague a pasta ou escolha outro caminho."
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

    /// Onde a worktree nasce: `<pai do repo>/worktrees/<repo>/<branch>`.
    ///
    /// Fora do repositório para não misturar com repositórios de verdade, e fora do
    /// diretório do app porque worktree é artefato de git — se o app sumir, o
    /// trabalho não deve ficar órfão dentro da config dele.
    ///
    /// Sem ponto no nome. Ele já custou: o Finder esconde pasta que começa com
    /// ponto, e worktree é pasta que se abre à mão — a de esconder era a única
    /// coisa que o ponto fazia, porque agrupar por repositório é o que mantém o
    /// caminho previsível e fácil de apagar. Worktree criada antes disto continua
    /// onde está e funcionando: o git guarda caminho absoluto.
    static func suggestedPath(repoRoot: String, branch: String) -> String {
        let repo = URL(fileURLWithPath: repoRoot)
        return repo.deletingLastPathComponent()
            .appendingPathComponent("worktrees")
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
    ///
    /// Sempre deriva um nome novo, e é o contrato certo para quem chama: a branch
    /// em que você está agora está tomada por definição.
    static func availableBranch(basedOn current: String, in path: String) -> String {
        let existing = branches(in: path)
        var n = 2
        while existing.contains("\(current)-\(n)") { n += 1 }
        return "\(current)-\(n)"
    }

    private static func branches(in path: String) -> [String] {
        (try? run(["branch", "--format=%(refname:short)", "--list"], in: path))?
            .split(whereSeparator: \.isNewline).map { String($0).trimmed } ?? []
    }

    // MARK: - O que vai acontecer com o nome que você escreveu

    /// O destino de um nome de branch, antes de mexer em disco.
    enum BranchPlan {
        /// Não existe em lugar nenhum: nasce do HEAD do repositório de origem.
        case new
        /// Já existe local e está livre: a worktree abre nela, no commit dela.
        case existingLocal
        /// Só existe no remoto. A local nasce seguindo essa ref.
        case remote(String)
        /// Já está aberta numa worktree. Não há o que criar — é aquela pasta.
        case alreadyCheckedOut(String)
    }

    /// Retrato das branches do repositório, lido de uma vez.
    ///
    /// O formulário precisa dizer, a cada tecla, o que vai acontecer com o nome
    /// digitado. Perguntar ao git por caractere são três processos por tecla na
    /// thread que está segurando um modal.
    struct BranchIndex {
        let local: Set<String>
        /// branch → ref remota (`origin/x`) de quem ainda não existe local.
        let remote: [String: String]
        /// branch → pasta da worktree que já a tem aberta.
        let checkedOut: [String: String]

        func plan(for branch: String) -> BranchPlan {
            if let path = checkedOut[branch] { return .alreadyCheckedOut(path) }
            if local.contains(branch) { return .existingLocal }
            if let ref = remote[branch] { return .remote(ref) }
            return .new
        }
    }

    static func index(of repo: String) -> BranchIndex {
        var checkedOut: [String: String] = [:]
        var stale = false

        func readWorktrees() {
            checkedOut = [:]
            let listing = (try? run(["worktree", "list", "--porcelain"], in: repo)) ?? ""
            var path: String?
            for line in listing.split(whereSeparator: \.isNewline) {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("branch refs/heads/"), let path {
                    let branch = String(line.dropFirst("branch refs/heads/".count))
                    if FileManager.default.fileExists(atPath: path) {
                        checkedOut[branch] = path
                    } else {
                        stale = true
                    }
                }
            }
        }

        readWorktrees()
        // Pasta apagada à mão deixa o registro do git para trás, e reaproveitá-lo
        // mandaria a sessão para um caminho que não existe. `prune` é idempotente.
        if stale {
            _ = try? run(["worktree", "prune"], in: repo)
            readWorktrees()
        }

        var remote: [String: String] = [:]
        let refs = (try? run(["for-each-ref", "--format=%(refname:short)", "refs/remotes"],
                             in: repo)) ?? ""
        for ref in refs.split(whereSeparator: \.isNewline).map({ String($0).trimmed }) {
            guard let slash = ref.firstIndex(of: "/") else { continue }
            let name = String(ref[ref.index(after: slash)...])
            // `origin/HEAD` é ponteiro para a branch padrão, não uma branch.
            guard name != "HEAD" else { continue }
            // `origin` ganha de outro remoto com o mesmo nome: é o que se quer
            // sem perguntar, e perguntar aqui seria um diálogo por tecla digitada.
            if remote[name] == nil || ref.hasPrefix("origin/") { remote[name] = ref }
        }

        return BranchIndex(local: Set(branches(in: repo)),
                           remote: remote,
                           checkedOut: checkedOut)
    }

    // MARK: - Criação

    struct Created {
        let path: String
        let branch: String
        /// Se as modificações em arquivos rastreados vieram junto, para relatar
        /// sem inventar.
        let carriedTrackedChanges: Bool
        /// A worktree já existia e foi reaproveitada — nada foi criado em disco.
        let reused: Bool
    }

    /// Abre a worktree de `branch` em `destination` — criando-a, ou devolvendo a
    /// que já existe.
    ///
    /// Quatro caminhos, e o nome que você escreveu decide qual:
    ///
    /// - branch que não existe → nasce do HEAD da origem
    /// - branch que existe local e está livre → a worktree abre **nela**, no
    ///   commit dela
    /// - branch que só existe no remoto → nasce local seguindo a ref remota
    /// - branch já aberta em outra worktree → é aquela pasta, e nada é criado
    ///
    /// Os três últimos faltavam. O app só sabia criar branch nova, e da recusa do
    /// git em ter a mesma branch em dois lugares concluía "escolha outro nome" —
    /// quando "já está aberta ali" é justamente a resposta útil. Sessão na
    /// `develop` não tinha como ir para uma `AGROS-3323` que já existia: o nome
    /// digitado era silenciosamente trocado por `AGROS-3323-2`, uma branch que
    /// ninguém pediu, sem o trabalho que estava na de verdade.
    static func create(from repoPath: String,
                       branch: String,
                       destination: String,
                       carryDirty: Bool) throws -> Created {
        let status = try status(of: repoPath)
        let plan = index(of: repoPath).plan(for: branch)

        let add: [String]
        switch plan {
        case .alreadyCheckedOut(let existing):
            Log.write("worktree: \(branch) já está aberta em \(existing) — reaproveitando "
                      + "em vez de criar")
            return Created(path: existing, branch: branch,
                           carriedTrackedChanges: false, reused: true)
        case .new:
            add = ["worktree", "add", "-b", branch, destination, "HEAD"]
        case .existingLocal:
            add = ["worktree", "add", destination, branch]
        case .remote(let ref):
            add = ["worktree", "add", "--track", "-b", branch, destination, ref]
        }

        guard !FileManager.default.fileExists(atPath: destination) else {
            throw Failure.destinationExists(destination)
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

        _ = try run(add, in: repoPath)

        // Branch nova sai do HEAD com árvore limpa, e ali o stash não tem com o
        // que conflitar. Branch que já existe tem histórico próprio: aplicar em
        // cima dela pode conflitar, e resolver conflito numa pasta que acabou de
        // nascer não é o que ninguém pediu. O objeto do stash fica criado e o log
        // diz como aplicá-lo à mão — nada se perde por não ter vindo junto.
        if !stash.isEmpty {
            if case .new = plan {
                _ = try run(["stash", "apply", stash], in: destination)
            } else {
                Log.write("worktree: \(destination) abriu em \(branch), que tem histórico "
                          + "próprio — as mudanças não commitadas de \(status.branch) NÃO "
                          + "vieram. Para levá-las: cd \(destination) && git stash apply \(stash)")
                stash = ""
            }
        }

        Log.write("worktree: \(destination) aberta na branch \(branch)"
                  + (stash.isEmpty ? "" : ", com as mudanças não commitadas"))

        return Created(path: destination,
                       branch: branch,
                       carriedTrackedChanges: !stash.isEmpty,
                       reused: false)
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

    /// De qual repositório uma pasta faz parte, sempre pelo checkout principal.
    ///
    /// `--show-toplevel` devolve a raiz da worktree LIGADA quando você está dentro
    /// de uma, e usá-la para criar a próxima aninha worktree dentro de worktree:
    /// medido em `.worktrees/back/.worktrees/so-o-back/vazamento`. Legal para o
    /// git, e um desastre em disco — apagar a de fora leva a de dentro, e a de
    /// fora fica cheia de arquivo que não é dela.
    static func mainRepo(of path: String) -> String? {
        guard let status = try? status(of: path) else { return nil }
        return mainWorktree(of: path) ?? status.repoRoot
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

        // Arquivo temporário, e não `Pipe`.
        //
        // A ponta de ESCRITA de um pipe é herdada por qualquer processo que o app
        // lance enquanto ela está aberta, e `readDataToEndOfFile` só retorna quando
        // TODAS as cópias fecham. O script de cópia da worktree roda fora da main
        // thread por minutos com `node_modules` no meio: herdada por ele, uma
        // chamada de milissegundos travava até a cópia acabar. Medido — 2min30 de
        // app congelado num `git rev-parse --show-toplevel`, e ele destravou no
        // segundo em que a cópia terminou.
        //
        // O fd de um arquivo também é herdado, e ali não custa nada: ninguém
        // depende de EOF para saber que acabou — quem diz isso é o `waitUntilExit`.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("egeon-git-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: scratch.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: scratch) }

        guard let sink = try? FileHandle(forWritingTo: scratch) else {
            throw Failure.git(command: arguments.joined(separator: " "),
                              output: "não consegui abrir \(scratch.path)")
        }
        task.standardOutput = sink
        task.standardError = sink

        try task.run()
        task.waitUntilExit()
        try? sink.close()

        let output = (try? String(contentsOf: scratch, encoding: .utf8)) ?? ""
        guard task.terminationStatus == 0 else {
            throw Failure.git(command: arguments.joined(separator: " "), output: output.trimmed)
        }
        return output
    }
}

// MARK: - Dizer antes de fazer

/// O que o formulário mostra embaixo do campo de branch, a cada tecla.
///
/// Existe porque as quatro saídas são diferentes o bastante para mudar o que o
/// botão "Criar" faz — de "nasce do commit atual" a "não cria nada, usa aquela
/// pasta". Descobrir isso depois, no log, é a definição do defeito que esta
/// mudança conserta.
extension Worktree.BranchPlan {
    /// A branch nasce agora, e portanto sai do HEAD da origem.
    var isFresh: Bool {
        if case .new = self { return true }
        return false
    }

    /// Uma linha, para a lista de terminais do formulário de duplicação.
    var short: String {
        switch self {
        case .new: return "branch nova"
        case .existingLocal: return "abre na branch que já existe"
        case .remote(let ref): return "nasce seguindo \(ref)"
        case .alreadyCheckedOut(let path):
            return "já aberta em \(NodeWorktreePlanner.short(path))"
        }
    }

    func summary(comingFrom current: String, dirty: Bool) -> String {
        switch self {
        case .new:
            return "Branch nova · sai de \(current), no commit atual."
                + (dirty ? " As mudanças não commitadas vão junto." : "")
        case .existingLocal:
            return "Esta branch já existe · a worktree abre nela, no commit dela."
                + (dirty ? " As mudanças não commitadas de \(current) ficam onde estão." : "")
        case .remote(let ref):
            return "Só existe em \(ref) · a branch local nasce seguindo o remoto."
                + (dirty ? " As mudanças não commitadas de \(current) ficam onde estão." : "")
        case .alreadyCheckedOut(let path):
            return "Já está aberta em \(NodeWorktreePlanner.short(path)) · nada é criado, "
                + "e é essa pasta que vai ser usada."
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
