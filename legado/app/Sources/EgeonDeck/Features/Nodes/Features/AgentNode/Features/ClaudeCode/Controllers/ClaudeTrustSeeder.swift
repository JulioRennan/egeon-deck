import Foundation

/// Grava, antes de o Claude subir, a confiança que a pasta herda do
/// repositório de onde saiu (ADR-071).
///
/// Só mexe nas três chaves de uma entrada, num arquivo que os `claude` em
/// execução também gravam: lê, muda e troca o arquivo de uma vez, como o
/// próprio CLI faz. Dois gravando no mesmo instante é possível, e o pior caso é
/// a marcação sumir e o diálogo voltar — conversa e ajustes não correm risco.
enum ClaudeTrustSeeder {
    /// `cwd` é a pasta onde o agente vai subir; `configDir`, o
    /// `CLAUDE_CONFIG_DIR` dele (nil = o padrão, `~/.claude.json`).
    static func prepare(cwd: String, configDir: String?) {
        guard let (target, origins) = sources(for: cwd), !origins.isEmpty else { return }

        let file = configFile(configDir)
        guard let data = try? Data(contentsOf: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updated = ClaudeTrust.inheriting(root, target: target, from: origins),
              let out = try? JSONSerialization.data(withJSONObject: updated,
                                                     options: [.prettyPrinted, .withoutEscapingSlashes])
        else { return }
        do {
            try out.write(to: file, options: .atomic)
            Log.write("confiança[claude]: \(target) herdou de "
                      + origins.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                      + " em \(file.path)")
        } catch {
            Log.write("confiança[claude]: não gravei \(file.path) — \(error.localizedDescription)")
        }
    }

    /// A pasta que o Claude vai consultar e de onde ela herda: worktree ligada
    /// herda do checkout principal; pasta fora de git (a do multi-projeto), dos
    /// repositórios de dentro. Checkout principal não herda de ninguém.
    static func sources(for cwd: String) -> (target: String, origins: [String])? {
        let path = real(cwd)
        guard let top = Worktree.topLevel(of: path) else {
            return (path, repositories(inside: path))
        }
        let target = real(top)
        guard let main = Worktree.mainWorktree(of: path).map(real),
              main != target else { return nil }
        return (target, [main])
    }

    /// O repositório principal de cada pasta git logo abaixo — o que o Claude
    /// usaria de chave se subisse nela.
    static func repositories(inside folder: String) -> [String] {
        let children = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return children.sorted().compactMap { name -> String? in
            let path = (folder as NSString).appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
            else { return nil }
            return Worktree.mainWorktree(of: path).map(real)
        }
    }

    /// O caminho como o Claude grava a chave: `realpath`. O
    /// `resolvingSymlinksInPath` do Foundation tira o `/private` de
    /// `/private/tmp` e `/private/var`, e a chave não casava.
    static func real(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func configFile(_ configDir: String?) -> URL {
        guard let configDir, !configDir.isEmpty else {
            return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json")
        }
        return URL(fileURLWithPath: (configDir as NSString).expandingTildeInPath)
            .appendingPathComponent(".claude.json")
    }
}
