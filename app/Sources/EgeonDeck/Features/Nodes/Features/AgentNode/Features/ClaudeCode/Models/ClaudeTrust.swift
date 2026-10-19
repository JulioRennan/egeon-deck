import Foundation

/// A confiança do Claude Code numa pasta, como ele guarda no `.claude.json`
/// (ADR-071).
///
/// O diálogo "você confia nesta pasta?" lê `projects[<pasta>]
/// .hasTrustDialogAccepted`, subindo pelos pais, e o próprio CLI sugere gravar
/// ali (binário 2.1.303). A pasta nova de toda worktree — de repositório ou a do
/// multi-projeto, que nem é git — não tem entrada, e a cada branch o Claude
/// perguntava de novo, e de novo pelos imports externos do CLAUDE.md, embora o
/// repositório de origem já fosse aceito.
enum ClaudeTrust {
    static let trust = "hasTrustDialogAccepted"
    static let includes = ["hasClaudeMdExternalIncludesApproved", "hasClaudeMdExternalIncludesWarningShown"]

    /// O que o Claude Code põe numa entrada nova de `projects` — sem estes
    /// campos ele lê `undefined` onde espera lista.
    static let blankProject: [String: Any] = [
        "allowedTools": [String](), "mcpContextUris": [String](), "mcpServers": [String: Any](),
        "enabledMcpjsonServers": [String](), "disabledMcpjsonServers": [String](),
        "hasTrustDialogAccepted": false, "hasClaudeMdExternalIncludesApproved": false,
        "hasClaudeMdExternalIncludesWarningShown": false,
    ]

    /// A entrada mais próxima, a da pasta ou a de um pai, que tem a chave ligada.
    static func granted(_ key: String, in projects: [String: Any], path: String) -> Bool {
        // Sem `standardizingPath`: ele tira o `/private` de `/private/tmp`, e a
        // chave do Claude é o `realpath`, com ele.
        var current = path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
        while true {
            if (projects[current] as? [String: Any])?[key] as? Bool == true { return true }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent.isEmpty { return false }
            current = parent
        }
    }

    /// O `.claude.json` com `target` herdando o que TODAS as origens já têm
    /// aceito. `nil` quando não há o que mudar: sem origem, origem não aceita,
    /// ou o alvo já aceito.
    ///
    /// Todas, e não alguma: a pasta junta os repositórios, e confiar nela é
    /// confiar em cada um.
    static func inheriting(_ root: [String: Any], target: String, from origins: [String]) -> [String: Any]? {
        guard !origins.isEmpty else { return nil }
        let projects = root["projects"] as? [String: Any] ?? [:]
        var entry = projects[target] as? [String: Any] ?? blankProject
        var changed = false
        for key in [trust] + includes {
            guard !granted(key, in: projects, path: target),
                  origins.allSatisfy({ granted(key, in: projects, path: $0) }) else { continue }
            entry[key] = true
            changed = true
        }
        guard changed else { return nil }
        var updated = root
        var all = projects
        all[target] = entry
        updated["projects"] = all
        return updated
    }
}
