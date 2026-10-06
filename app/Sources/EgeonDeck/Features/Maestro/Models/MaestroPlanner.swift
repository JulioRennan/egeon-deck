import CoreGraphics
import Foundation

/// O que o planejador precisa saber do mundo, entregue por quem chama: assim
/// a decisão inteira roda em teste, sem app, sem disco e sem pty.
struct MaestroContext {
    /// Quem está aplicando — o nó maestro. Fica fora do plano (ADR-066).
    var caller: String
    var profiles: [String: AgentProfile]
    var catalog: (AgentProfile) -> ModelCatalog? = { _ in nil }
    /// Ids dos nós em turno ou parados num pedido de permissão: reiniciar
    /// perderia o que ele está fazendo.
    var working: Set<String> = []
    /// Ids dos nós em segundo plano — esperando um vizinho ou com processo
    /// rodando; só com `force` (ADR-066).
    var background: Set<String> = []
    var directoryExists: (String) -> Bool = { path in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
    /// A configuração do CLI que o workspace usa por último — a mesma sugestão
    /// do formulário de terminal novo.
    var suggestedConfig: (String) -> String? = { _ in nil }
    /// As configurações que o maestro pode escolher para um CLI: as que existem
    /// no padrão dele (`configGlob`). Pasta arbitrária não — seria apontar um
    /// agente para um settings preparado com permissões abertas.
    var knownConfigs: (AgentProfile) -> [String] = { $0.discoveredConfigs.map(\.path) }
}

/// O resultado de um plano: a bancada como ficaria e o que muda no que está
/// na tela. Com `errors` não vazio, nada disto vale.
struct MaestroOutcome {
    var errors: [String] = []
    var next: WorkbenchConfig
    /// Nós que nascem agora, na ordem do plano.
    var created: [String] = []
    /// Nós que mudam e precisam de processo novo (o system prompt e as flags
    /// só são lidos no arranque).
    var restarted: [String] = []
    var removed: [String] = []
    /// Dos reiniciados, os que mudaram de pasta, configuração ou CLI: o CLI
    /// guarda a conversa por pasta e por configuração, e retomar ali falharia
    /// calado numa conversa nova — então ela é zerada de propósito.
    var freshConversation: [String] = []
    var edgesChanged = false
    var rulesChanged = false
    var visitsChanged = false
    /// Os cards foram rearrumados: os frames de `next` são os novos.
    var relaid = false

    var changed: Bool {
        !created.isEmpty || !restarted.isEmpty || !removed.isEmpty
            || edgesChanged || rulesChanged || visitsChanged || relaid
    }

    /// Uma linha para a trilha e para a resposta: `+front ~revisor −velho ·
    /// arestas · regras da bancada`.
    var summary: String {
        var parts: [String] = []
        let nodes = created.map { "+\($0)" } + restarted.map { "~\($0)" } + removed.map { "−\($0)" }
        if !nodes.isEmpty { parts.append(nodes.joined(separator: " ")) }
        if edgesChanged { parts.append("\(next.edgeList.count) aresta(s)") }
        if rulesChanged { parts.append("regras da bancada") }
        if visitsChanged { parts.append("maxVisits \(next.visitLimit)") }
        if relaid { parts.append("canvas rearrumado") }
        return parts.isEmpty ? "nada muda" : parts.joined(separator: " · ")
    }
}

/// Valida um plano contra a bancada e calcula a bancada seguinte (ADR-066).
///
/// Não aplica nada: só decide. Quem aplica é o `MaestroController`, e só
/// quando aqui não sobrou erro — o plano vale inteiro ou não vale.
enum MaestroPlanner {
    /// Tetos do que o maestro pode afrouxar. As guardas de cadeia existem para
    /// quando ninguém está olhando, e quem as tira de vez é o usuário (ADR-066).
    static let maxSendsCeiling = 10
    /// Menor que isto o terminal não mostra uma linha de prompt inteira.
    static let minimumSize = CGSize(width: 320, height: 200)
    static let visitCeiling = 12

    static func plan(_ plan: MaestroPlan, on bench: WorkbenchConfig,
                     context: MaestroContext) -> MaestroOutcome {
        var out = MaestroOutcome(next: bench)
        var errors: [String] = []

        // Ids: slug, únicos, e nunca o próprio maestro.
        var seen = Set<String>()
        for node in plan.nodes {
            if node.id != NodeTemplateStore.identifier(from: node.id) {
                errors.append("nó '\(node.id)': id tem de ser minúsculo, com letras, números, - ou _ "
                              + "(ex.: '\(NodeTemplateStore.identifier(from: node.id))')")
            }
            if node.id == context.caller {
                errors.append("nó '\(node.id)': é você — o maestro não se reconfigura pelo plano "
                              + "(reiniciar mataria este turno). Peça ao usuário no seletor do card.")
            }
            if !seen.insert(node.id).inserted {
                errors.append("nó '\(node.id)' aparece duas vezes em nodes")
            }
        }
        for id in plan.remove {
            if id == context.caller { errors.append("remove '\(id)': é você — o maestro não se remove") }
            else if let node = bench.nodes.first(where: { $0.id == id }) {
                if node.isMaestro { errors.append("remove '\(id)': é maestro — só o usuário o remove") }
            } else {
                errors.append("remove '\(id)': não existe nesta bancada")
            }
            if seen.contains(id) { errors.append("'\(id)' está em nodes e em remove ao mesmo tempo") }
        }

        // Nós: upsert, validado depois de montado — é o nó final que tem de
        // fazer sentido, não cada campo isolado.
        var next = bench
        for patch in plan.nodes where patch.id != context.caller {
            if let position = next.nodes.firstIndex(where: { $0.id == patch.id }) {
                let current = next.nodes[position]
                if current.isMaestro {
                    errors.append("nó '\(patch.id)': é maestro — só o usuário mexe em outro maestro")
                    continue
                }
                guard current.type == .agent || current.type == .shell else {
                    errors.append("nó '\(patch.id)': é \(current.type.rawValue) — o maestro só mexe em agent e shell")
                    continue
                }
                let (updated, problems) = apply(patch, to: current, context: context)
                errors += problems
                errors += validate(updated, previous: current, in: bench, context: context)
                next.nodes[position] = updated
                if needsRestart(current, updated) { out.restarted.append(patch.id) }
                if updated.conversationId == nil, current.conversationId != nil {
                    out.freshConversation.append(patch.id)
                }
            } else {
                let (created, problems) = create(patch, context: context)
                errors += problems
                if let created {
                    errors += validate(created, previous: nil, in: bench, context: context)
                    next.nodes.append(created)
                    out.created.append(patch.id)
                }
            }
        }

        let removed = Set(plan.remove).subtracting([context.caller])
        next.nodes.removeAll { removed.contains($0.id) }
        out.removed = plan.remove.filter { id in removed.contains(id) && bench.nodes.contains { $0.id == id } }

        // Bancada.
        switch plan.rules {
        case .keep: break
        case .clear: next.rules = nil
        case .set(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            next.rules = trimmed.isEmpty ? nil : trimmed
        }
        out.rulesChanged = next.rules != bench.rules
        switch plan.maxVisits {
        case .keep: break
        case .clear: next.maxVisits = nil
        case .set(let n):
            if n < 1 || n > visitCeiling {
                errors.append("maxVisits tem de ficar entre 1 e \(visitCeiling)")
            } else { next.maxVisits = n }
        }
        out.visitsChanged = next.visitLimit != bench.visitLimit

        // Arestas. Primeiro some o que aponta para nó removido, depois o que
        // o plano diz. Nó novo não ganha seta para o maestro: a ligação dele
        // com cada terminal é implícita (`MaestroLinks`).
        let ids = Set(next.nodes.map(\.id))
        var edges = bench.edgeList.filter { ids.contains($0.from) && ids.contains($0.to) }
        for edge in plan.edges {
            var ok = true
            for end in [edge.from, edge.to] where !ids.contains(end) {
                errors.append("aresta \(edge.from)→\(edge.to): '\(end)' não existe "
                              + (removed.contains(end) ? "(está em remove)" : "nesta bancada nem no plano"))
                ok = false
            }
            if edge.from == edge.to {
                errors.append("aresta \(edge.from)→\(edge.to): um nó não se liga a si mesmo")
                ok = false
            }
            switch edge.maxSends {
            case .set(let n) where n < 1 || n > maxSendsCeiling:
                errors.append("aresta \(edge.from)→\(edge.to): maxSends tem de ficar entre 1 e \(maxSendsCeiling)")
                ok = false
            case .clear:
                errors.append("aresta \(edge.from)→\(edge.to): sem limite (null) só o usuário põe — "
                              + "use um número até \(maxSendsCeiling)")
                ok = false
            default: break
            }
            guard ok else { continue }
            let pairs = edge.both ? [(edge.from, edge.to), (edge.to, edge.from)] : [(edge.from, edge.to)]
            for (from, to) in pairs {
                if let i = edges.firstIndex(of: EdgeConfig(from: from, to: to)) {
                    edges[i].maxSends = edge.maxSends.applied(to: edges[i].maxSends)
                } else {
                    var fresh = EdgeConfig(from: from, to: to)
                    if !edge.maxSends.isKeep { fresh.maxSends = edge.maxSends.applied(to: nil) }
                    edges.append(fresh)
                }
            }
        }
        for cut in plan.unlink {
            let pairs = cut.both ? [(cut.from, cut.to), (cut.to, cut.from)] : [(cut.from, cut.to)]
            var found = false
            for (from, to) in pairs {
                let before = edges.count
                edges.removeAll { $0 == EdgeConfig(from: from, to: to) }
                found = found || edges.count != before
            }
            // Aresta de nó removido já saiu junto com ele: pedir de novo não é erro.
            let gone = removed.contains(cut.from) || removed.contains(cut.to)
            if !found && !gone { errors.append("unlink \(cut.from)→\(cut.to): essa aresta não existe") }
        }
        next.edges = edges.isEmpty ? (bench.edges == nil ? nil : []) : edges
        out.edgesChanged = !sameEdges(next.edgeList, bench.edgeList)

        // O time mudou: o canvas é rearrumado, a menos que o plano diga não.
        if plan.layout ?? (!out.created.isEmpty || !out.removed.isEmpty) {
            let frames = MaestroLayout.frames(for: next.nodes, edges: next.edgeList)
            for i in next.nodes.indices {
                if let frame = frames[next.nodes[i].id] { next.nodes[i].setFrame(frame) }
            }
        }
        // O lugar que o maestro deu à mão vence o arranjo — vem depois dele.
        for patch in plan.nodes where patch.id != context.caller {
            guard let wanted = patch.frame,
                  let i = next.nodes.firstIndex(where: { $0.id == patch.id }) else { continue }
            let base = next.nodes[i].frame ?? CGRect(origin: .zero, size: MaestroLayout.agent)
            let rect = CGRect(x: wanted.x ?? base.minX, y: wanted.y ?? base.minY,
                              width: wanted.w ?? base.width, height: wanted.h ?? base.height)
            if rect.minX < 0 || rect.minY < 0 {
                errors.append("nó '\(patch.id)': frame fora do canvas — x e y começam em 0")
            } else if rect.width < minimumSize.width || rect.height < minimumSize.height {
                errors.append("nó '\(patch.id)': frame pequeno demais — mínimo "
                              + "\(Int(minimumSize.width))×\(Int(minimumSize.height))")
            } else {
                next.nodes[i].setFrame(rect)
            }
        }
        out.relaid = next.nodes.contains { node in
            node.frame != nil && bench.nodes.first { $0.id == node.id }?.frame != node.frame
        }

        // Regra da bancada nova só sobe com processo novo: os outros agentes
        // reiniciam. O maestro não — as dele valem no próximo arranque.
        if out.rulesChanged {
            for node in next.nodes where node.type == .agent && node.id != context.caller
                && !out.created.contains(node.id) && !out.restarted.contains(node.id) {
                out.restarted.append(node.id)
            }
        }

        // Reiniciar ou remover quem está trabalhando perde o turno dele.
        let touched = out.restarted + out.removed
        let inTurn = touched.filter(context.working.contains)
        if !inTurn.isEmpty {
            errors.append("trabalhando agora: \(inTurn.joined(separator: ", ")) — este plano "
                          + "reiniciaria ou removeria, e o turno se perderia. Espere terminar e mande de novo.")
        }
        let behind = touched.filter(context.background.contains)
        if !behind.isEmpty && !plan.force {
            errors.append("em segundo plano: \(behind.joined(separator: ", ")) — pode ser só esperando "
                          + "um vizinho, ou um processo rodando. Confira com `egeon peek`; se puder "
                          + "interromper, mande o mesmo plano com \"force\": true.")
        }

        out.next = next
        out.errors = errors
        return out
    }

    // MARK: - Nós

    private static func create(_ patch: MaestroPlan.Node,
                               context: MaestroContext) -> (NodeConfig?, [String]) {
        let kind = patch.kind ?? .agent
        guard kind == .agent || kind == .shell else {
            return (nil, ["nó '\(patch.id)': kind '\(kind.rawValue)' — o maestro cria agent ou shell"])
        }
        var node = NodeConfig(type: kind, id: patch.id)
        if kind == .agent {
            let cli: String?
            switch patch.cli {
            case .set(let value): cli = value
            case .keep, .clear: cli = context.profiles["claude"] != nil ? "claude" : context.profiles.keys.sorted().first
            }
            node.agent = cli
            node.config = cli.flatMap(context.suggestedConfig)
        }
        var (filled, problems) = apply(patch, to: node, context: context, isNew: true)
        filled.component = "maestro"
        if kind == .agent, filled.agent == nil { problems.append("nó '\(patch.id)': falta 'cli'") }
        return (filled, problems)
    }

    private static func apply(_ patch: MaestroPlan.Node, to current: NodeConfig,
                              context: MaestroContext, isNew: Bool = false) -> (NodeConfig, [String]) {
        var node = current
        var problems: [String] = []
        let label = "nó '\(patch.id)'"

        if let kind = patch.kind, kind != current.type, !isNew {
            problems.append("\(label): é \(current.type.rawValue) e não vira \(kind.rawValue) — "
                            + "remova e crie de novo com outro id")
        }

        if node.type == .agent, !isNew {
            switch patch.cli {
            case .keep: break
            case .clear: problems.append("\(label): 'cli' não pode ser null num agente")
            case .set(let cli) where cli != node.agent:
                // A conversa é do outro programa, e o que era dele não serve.
                node = node.withoutConversation
                node.agent = cli
                node.cmd = nil
                node.model = nil
                node.effort = nil
                node.ultracode = nil
                node.config = context.suggestedConfig(cli)
            case .set: break
            }
        }
        if node.type == .shell {
            for (name, field) in [("cli", patch.cli), ("model", patch.model), ("effort", patch.effort),
                                  ("role", patch.role), ("rules", patch.rules), ("config", patch.config)]
            where !field.isKeep {
                problems.append("\(label): '\(name)' é de agente; este é shell")
            }
            if case .set = patch.ultracode { problems.append("\(label): 'ultracode' é de agente; este é shell") }
        }

        node.model = clean(patch.model.applied(to: node.model))
        node.effort = clean(patch.effort.applied(to: node.effort))
        node.ultracode = patch.ultracode.applied(to: node.ultracode) == true ? true : nil
        node.cwd = clean(patch.cwd.applied(to: node.cwd))
        node.config = clean(patch.config.applied(to: node.config))
        if node.type == .shell {
            node.cmd = clean(patch.cmd.applied(to: node.cmd))
        } else if !patch.cmd.isKeep {
            problems.append("\(label): 'cmd' é de shell — o comando do agente é o do CLI")
        }
        // A conversa do CLI é da pasta e da configuração em que nasceu: com
        // outra, o `--resume` falha e o terminal abre uma nova calado.
        if !isNew, node.cwd != current.cwd || node.config != current.config {
            node = node.withoutConversation
        }

        // Papel e regras escritos aqui são os que sobem: a exceção do CLI em
        // uso, se havia, cederia o lugar ao que o maestro acabou de escrever
        // só no papel — e o nó continuaria com o texto antigo (ADR-057).
        if !patch.role.isKeep {
            node.prompt = clean(patch.role.applied(to: node.prompt))
            node.byAgent = dropping(\.prompt, of: node.agent, in: node.byAgent)
        }
        if !patch.rules.isKeep {
            node.rules = clean(patch.rules.applied(to: node.rules))
            node.byAgent = dropping(\.rules, of: node.agent, in: node.byAgent)
        }
        return (node, problems)
    }

    /// Confere só o que o plano mudou (ou tudo, num nó novo): um nó do usuário
    /// com modelo antigo escrito à mão não pode travar um plano que só mexe no
    /// papel dele.
    private static func validate(_ node: NodeConfig, previous: NodeConfig?, in bench: WorkbenchConfig,
                                 context: MaestroContext) -> [String] {
        var problems: [String] = []
        let label = "nó '\(node.id)'"
        let sameCLI = previous?.agent == node.agent
        func changed<T: Equatable>(_ path: KeyPath<NodeConfig, T>) -> Bool {
            previous.map { $0[keyPath: path] != node[keyPath: path] } ?? true
        }

        if let cwd = node.cwd, changed(\.cwd) {
            let resolved = WorkbenchConfig.resolve(cwd: cwd, against: bench.url)
            if !context.directoryExists(resolved) {
                problems.append("\(label): pasta '\(cwd)' não existe (resolve em \(resolved))")
            }
        }
        guard node.type == .agent else { return problems }

        guard let key = node.agent, let profile = context.profiles[key] else {
            let known = context.profiles.keys.sorted().joined(separator: ", ")
            return problems + ["\(label): CLI '\(node.agent ?? "")' não existe — disponíveis: \(known)"]
        }
        if let config = node.config, changed(\.config) || !sameCLI {
            let wanted = URL(fileURLWithPath: (config as NSString).expandingTildeInPath).standardized.path
            let allowed = (context.knownConfigs(profile) + [context.suggestedConfig(key)].compactMap { $0 })
                .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardized.path }
            if !allowed.contains(wanted) {
                problems.append("\(label): config '\(config)' não está entre as de \(profile.displayName) — "
                                + "use uma de `configs` em `egeon models`")
            }
        }

        let catalog = context.catalog(profile)
        var chosen: ModelCatalog.Model?
        if let model = node.model, changed(\.model) || !sameCLI {
            if !profile.offersModels {
                problems.append("\(label): \(profile.displayName) não aceita escolher modelo")
            } else if let catalog, !catalog.models.isEmpty {
                chosen = catalog.model(for: model)
                if chosen == nil {
                    problems.append("\(label): modelo '\(model)' não existe no \(profile.displayName) — "
                                    + "veja `egeon models`")
                }
            } else if let listed = profile.models, !listed.isEmpty, !listed.contains(model) {
                problems.append("\(label): modelo '\(model)' não está entre \(listed.joined(separator: ", "))")
            }
        }
        if let effort = node.effort, changed(\.effort) || changed(\.model) || !sameCLI {
            if !profile.offersEfforts {
                problems.append("\(label): \(profile.displayName) não aceita escolher esforço")
            } else if let chosen {
                if chosen.efforts.isEmpty {
                    problems.append("\(label): \(chosen.label) não tem nível de esforço — tire 'effort'")
                } else if !chosen.efforts.contains(effort) {
                    problems.append("\(label): \(chosen.label) não tem esforço '\(effort)' — aceita "
                                    + chosen.efforts.joined(separator: ", "))
                }
            } else {
                // Sem modelo escolhido, o padrão do CLI decide — e qualquer
                // nível que algum modelo dele tenha é plausível.
                let known = Set((catalog?.models ?? []).flatMap(\.efforts) + (profile.efforts ?? []))
                if !known.isEmpty, !known.contains(effort) {
                    problems.append("\(label): esforço '\(effort)' não existe no \(profile.displayName) — "
                                    + "aceitos: \(known.sorted().joined(separator: ", "))")
                }
            }
        }
        if node.ultracode == true, profile.ultracode == nil {
            problems.append("\(label): \(profile.displayName) não tem ultracode")
        }
        return problems
    }

    /// Mesma régua do formulário (`editNode`): o que entra na linha de comando
    /// ou no system prompt só vale com processo novo.
    static func needsRestart(_ a: NodeConfig, _ b: NodeConfig) -> Bool {
        a.type != b.type || a.agent != b.agent || a.model != b.model || a.effort != b.effort
            || a.ultracode != b.ultracode || a.cmd != b.cmd || a.config != b.config
            || a.cwd != b.cwd || a.effectivePrompt != b.effectivePrompt
            || a.effectiveRules != b.effectiveRules
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func dropping(_ field: WritableKeyPath<NodeTemplate.Overrides, String?>,
                                 of cli: String?,
                                 in map: [String: NodeTemplate.Overrides]?) -> [String: NodeTemplate.Overrides]? {
        guard let cli, var map, var over = map[cli], over[keyPath: field] != nil else { return map }
        over[keyPath: field] = nil
        map[cli] = over.isEmpty ? nil : over
        return map.isEmpty ? nil : map
    }

    private static func sameEdges(_ a: [EdgeConfig], _ b: [EdgeConfig]) -> Bool {
        guard a.count == b.count else { return false }
        return a.allSatisfy { edge in
            b.contains { $0 == edge && $0.maxSends == edge.maxSends }
        }
    }
}
