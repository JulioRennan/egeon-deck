import Foundation

/// O que o maestro lê antes de desenhar: a bancada como está e o que cada CLI
/// aceita (ADR-066). Dicionário pronto para JSON, porque é isso que volta
/// pelo socket.
enum MaestroSnapshot {
    /// A bancada no MESMO vocabulário do plano (`cli`, `role`), para o maestro
    /// poder copiar um nó daqui para lá e mudar só o que quer. `state`, `you` e
    /// `maestro` são só de leitura — o plano os aceita e ignora.
    static func bench(_ bench: WorkbenchConfig, caller: String,
                      activity: (String) -> Activity?) -> [String: Any] {
        var payload: [String: Any] = [
            "workbench": bench.name,
            "path": bench.path,
            "you": caller,
            "maxVisits": bench.visitLimit,
            "nodes": bench.nodes.map { node(of: $0, caller: caller, activity: activity($0.id)) },
            "edges": bench.edgeList.map { edge -> [String: Any] in
                ["from": edge.from, "to": edge.to, "maxSends": edge.maxSends.map { $0 as Any } ?? NSNull()]
            },
        ]
        if let rules = bench.rules { payload["rules"] = rules }
        payload["note"] = "edges são as desenhadas; o maestro alcança todo terminal sem aresta, "
            + "e todo agente alcança o maestro"
        return payload
    }

    static func node(of node: NodeConfig, caller: String, activity: Activity?) -> [String: Any] {
        var out: [String: Any] = ["id": node.id, "kind": node.type.rawValue]
        if node.type == .agent {
            out["cli"] = node.agent ?? NSNull()
            out["model"] = node.model ?? NSNull()
            out["effort"] = node.effort ?? NSNull()
            if node.ultracode == true { out["ultracode"] = true }
            if let role = node.effectivePrompt { out["role"] = role }
            if let rules = node.effectiveRules { out["rules"] = rules }
            if let config = node.config { out["config"] = config }
        }
        if node.type == .shell, let cmd = node.cmd { out["cmd"] = cmd }
        if let cwd = node.cwd { out["cwd"] = cwd }
        if let frame = node.frame {
            out["frame"] = ["x": Int(frame.minX), "y": Int(frame.minY),
                            "w": Int(frame.width), "h": Int(frame.height)]
        }
        if node.isMaestro { out["maestro"] = true }
        if node.id == caller { out["you"] = true }
        if let activity { out["state"] = state(activity) }
        return out
    }

    /// Estado em palavra fixa, não o rótulo da tela: é o que o maestro compara.
    static func state(_ activity: Activity) -> String {
        switch activity {
        case .starting: return "starting"
        case .ready: return "idle"
        case .working: return "working"
        case .background: return "background"
        case .awaiting: return "awaiting"
        case .waiting: return "done"
        case .asking: return "asking"
        case .dead: return "dead"
        }
    }

    /// Os CLIs que existem, com modelos e níveis. Modelo do catálogo do binário
    /// quando há (ADR-064); senão os apelidos do `agents.json`.
    static func models(profiles: [String: AgentProfile],
                       catalog: (AgentProfile) -> ModelCatalog?) -> [String: Any] {
        let clis = profiles.keys.sorted().map { key -> [String: Any] in
            let profile = profiles[key]!
            var out: [String: Any] = ["cli": key, "name": profile.displayName,
                                      "acceptsModel": profile.offersModels,
                                      "acceptsEffort": profile.offersEfforts,
                                      "ultracode": profile.ultracode != nil]
            if let catalog = catalog(profile), !catalog.models.isEmpty {
                out["models"] = (catalog.featured + catalog.older).map { model -> [String: Any] in
                    var entry: [String: Any] = ["id": model.id, "label": model.label,
                                                "family": model.family, "efforts": model.efforts]
                    if let auto = model.defaultEffort { entry["defaultEffort"] = auto }
                    return entry
                }
            } else if let listed = profile.models, !listed.isEmpty {
                out["models"] = listed.map { ["id": $0] }
            }
            if let efforts = profile.efforts, !efforts.isEmpty { out["efforts"] = efforts }
            let configs = profile.discoveredConfigs.map(\.path)
            if !configs.isEmpty { out["configs"] = configs }
            return out
        }
        return ["clis": clis,
                "note": "model aceita o id ou o apelido da família (opus, sonnet, haiku); "
                    + "effort tem de estar em efforts do modelo escolhido"]
    }
}
