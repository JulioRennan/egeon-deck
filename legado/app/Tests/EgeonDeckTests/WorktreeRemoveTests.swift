import XCTest
@testable import EgeonDeck

/// Apagar a worktree pelo diálogo de remover a bancada.
///
/// O git desfaz o REGISTRO antes de terminar de apagar a árvore e não volta
/// atrás: morreu no meio — um arquivo criado durante a remoção, uma pasta sem
/// permissão —, ela já não existe para o git. O app tratava isso como "não deu"
/// e segurava a bancada; na segunda tentativa a pasta já não era reconhecida
/// como worktree, a bancada saía e o lixo ficava no disco.
final class WorktreeRemoveTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("egeon-worktree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Um dos testes tranca uma pasta para o git falhar; destrancar antes,
        // senão o temporário fica para trás.
        if let walk = FileManager.default.enumerator(atPath: root.path) {
            for case let item as String in walk {
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: root.appendingPathComponent(item).path)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git"] + arguments
        task.currentDirectoryURL = directory
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Repositório com um commit e uma worktree aberta em `feat`.
    private func repoWithWorktree() throws -> (repo: URL, worktree: URL) {
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try git(["init", "-q", "."], in: repo)
        try git(["config", "user.email", "teste@egeon"], in: repo)
        try git(["config", "user.name", "teste"], in: repo)
        try "a".write(to: repo.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "-A"], in: repo)
        try git(["commit", "-qm", "init"], in: repo)

        let worktree = root.appendingPathComponent("wts/feat")
        try git(["worktree", "add", "-b", "feat", worktree.path], in: repo)
        return (repo, worktree)
    }

    func testRemovesTheFolderAndTheRegistration() throws {
        let (repo, worktree) = try repoWithWorktree()
        XCTAssertTrue(Worktree.isRegistered(worktree.path, in: repo.path))

        // Suja como a de verdade nasce: arquivos novos e ignorados copiados.
        try "x".write(to: worktree.appendingPathComponent("novo.txt"),
                      atomically: true, encoding: .utf8)

        try Worktree.remove(worktree.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertFalse(Worktree.isRegistered(worktree.path, in: repo.path))
    }

    /// `isRegistered` compara caminhos resolvidos: em macOS o temporário é
    /// `/var/…` de um lado e `/private/var/…` do outro, e comparar texto cru
    /// diria "não registrada" para a worktree que está ali.
    func testRegistrationLookupSurvivesSymlinkedPaths() throws {
        let (repo, worktree) = try repoWithWorktree()
        // O mesmo lugar escrito do outro jeito: `/var/folders/…` e
        // `/private/var/folders/…` são a mesma pasta, e cada ponta do app pega
        // uma das duas formas.
        let outra = worktree.path.hasPrefix("/private/")
            ? String(worktree.path.dropFirst("/private".count))
            : "/private" + worktree.path
        XCTAssertNotEqual(outra, worktree.path, "o caminho do teste não tem symlink para exercitar")
        XCTAssertTrue(Worktree.isRegistered(outra, in: repo.path),
                      "o caminho com symlink deixou de reconhecer a worktree")
    }

    /// O estado em que o git deixa as coisas quando desiste no meio: registro
    /// já desfeito, pasta ainda no disco. Terminar de apagar é o que foi pedido.
    func testFinishesTheRemovalGitGaveUpOn() throws {
        let leftover = root.appendingPathComponent("wts/meio-apagada")
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try "sobra".write(to: leftover.appendingPathComponent("resto.txt"),
                          atomically: true, encoding: .utf8)

        XCTAssertTrue(try Worktree.finishRemoval(of: leftover.path, registered: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path))
    }

    /// Worktree ainda registrada é erro de verdade do git — a pasta fica e a
    /// mensagem sobe. Apagar aqui seria passar por cima de uma recusa legítima.
    func testKeepsTheFolderWhileTheWorktreeIsStillRegistered() throws {
        let (repo, worktree) = try repoWithWorktree()
        XCTAssertFalse(try Worktree.finishRemoval(of: worktree.path, registered: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.path))
        XCTAssertTrue(Worktree.isRegistered(worktree.path, in: repo.path))
    }

    /// O bug como ele aparece: alguém escrevendo na worktree enquanto ela é
    /// apagada — o watcher do editor, um `npm run dev` num terminal da bancada.
    /// O git morre com "Directory not empty" depois de já ter desfeito o
    /// registro, e o app precisa terminar o serviço. Com ou sem corrida o
    /// desfecho é o mesmo: pasta e registro fora.
    func testRemovalFinishesEvenWithSomebodyWritingInTheFolder() throws {
        let (repo, worktree) = try repoWithWorktree()
        let ruido = worktree.appendingPathComponent("build")
        try FileManager.default.createDirectory(at: ruido, withIntermediateDirectories: true)
        for i in 0..<40 {
            try "x".write(to: ruido.appendingPathComponent("f\(i).txt"),
                          atomically: true, encoding: .utf8)
        }

        // Um watcher: escreve em rajada por um instante e se cala — como o do
        // editor quando a pasta que ele observa começa a sumir.
        let escrevendo = DispatchSemaphore(value: 0)
        let parou = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            escrevendo.signal()
            for i in 0..<250 {
                try? "y".write(to: ruido.appendingPathComponent("race\(i).tmp"),
                               atomically: false, encoding: .utf8)
            }
            parou.signal()
        }
        escrevendo.wait()

        try Worktree.remove(worktree.path)
        parou.wait()

        XCTAssertFalse(Worktree.isRegistered(worktree.path, in: repo.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktree.path),
                       "sobrou pasta órfã — é o lixo que o bug deixava no disco")
    }

    /// O caminho inteiro quando o git morre no meio: ele já desfez o registro, e
    /// o app tenta terminar. Aqui nem o app consegue (a pasta está trancada), e
    /// o que sobe é a mensagem que diz exatamente isso — não o "use --force" do
    /// git, que não ajudaria ninguém.
    func testReportsLeftoversWhenNobodyCanDeleteTheFolder() throws {
        let (repo, worktree) = try repoWithWorktree()
        let trancada = worktree.appendingPathComponent("vendor")
        try FileManager.default.createDirectory(at: trancada, withIntermediateDirectories: true)
        try "z".write(to: trancada.appendingPathComponent("z.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o500],
                                              ofItemAtPath: trancada.path)

        XCTAssertThrowsError(try Worktree.remove(worktree.path)) { error in
            guard case Worktree.Failure.leftovers = error else {
                return XCTFail("erro inesperado: \(error)")
            }
        }
        XCTAssertFalse(Worktree.isRegistered(worktree.path, in: repo.path),
                       "o git não volta atrás: o registro já foi mesmo tendo falhado")
    }

    /// Pasta que já não existe não é falha: a faxina não tem o que fazer.
    func testNothingToFinishWhenTheFolderIsAlreadyGone() throws {
        XCTAssertTrue(try Worktree.finishRemoval(
            of: root.appendingPathComponent("nunca-existiu").path, registered: false))
    }
}
