import Foundation

/// Um campo do plano em três estados, porque o JSON tem três: chave ausente
/// mantém o que o nó tem, `null` volta ao padrão do CLI, valor troca.
///
/// `Optional` sozinho junta os dois primeiros, e aí "não mexa no modelo" e
/// "volte o modelo ao padrão" seriam o mesmo pedido.
enum PlanField<T: Equatable>: Equatable {
    case keep
    case clear
    case set(T)

    func applied(to current: T?) -> T? {
        switch self {
        case .keep: return current
        case .clear: return nil
        case .set(let value): return value
        }
    }

    var isKeep: Bool { self == .keep }
}

/// O desenho de uma bancada que o maestro manda aplicar (ADR-066).
///
/// Declarativo e inteiro: o plano é validado antes de qualquer efeito e
/// recusado inteiro se algo não fecha. Meia bancada montada é pior que nenhuma.
struct MaestroPlan: Equatable {
    struct Node: Equatable {
        var id: String
        var kind: NodeKind?
        var cli: PlanField<String> = .keep
        var model: PlanField<String> = .keep
        var effort: PlanField<String> = .keep
        var ultracode: PlanField<Bool> = .keep
        var role: PlanField<String> = .keep
        var rules: PlanField<String> = .keep
        var cwd: PlanField<String> = .keep
        var config: PlanField<String> = .keep
        /// O comando que um terminal `shell` roda ao subir (servidor de dev,
        /// watcher, teste em laço). Agente não tem: o comando dele é o do CLI.
        var cmd: PlanField<String> = .keep
        /// Onde o card fica no canvas. Vence o arranjo automático.
        var frame: Frame?
    }

    /// Posição e tamanho de um card, no documento do canvas (y cresce para
    /// baixo). Cada campo é opcional: só `x`/`y` move, só `w`/`h` redimensiona.
    struct Frame: Equatable, Decodable {
        var x: Double?
        var y: Double?
        var w: Double?
        var h: Double?

        enum Keys: String, CodingKey, CaseIterable { case x, y, w, h }

        init(x: Double? = nil, y: Double? = nil, w: Double? = nil, h: Double? = nil) {
            self.x = x; self.y = y; self.w = w; self.h = h
        }

        init(from decoder: Decoder) throws {
            try PlanKeys.check(decoder, Keys.self, path: "frame")
            let c = try decoder.container(keyedBy: Keys.self)
            x = try c.decodeIfPresent(Double.self, forKey: .x)
            y = try c.decodeIfPresent(Double.self, forKey: .y)
            w = try c.decodeIfPresent(Double.self, forKey: .w)
            h = try c.decodeIfPresent(Double.self, forKey: .h)
        }
    }

    struct Edge: Equatable {
        var from: String
        var to: String
        /// Ida e volta: cria (ou ajusta) as duas setas.
        var both: Bool = false
        /// Ausente: aresta nova nasce com o padrão, a que existe fica como está.
        /// `null`: sem limite próprio, só o teto da bancada.
        var maxSends: PlanField<Int> = .keep
    }

    struct Unlink: Equatable {
        var from: String
        var to: String
        var both: Bool = false
    }

    var rules: PlanField<String> = .keep
    var maxVisits: PlanField<Int> = .keep
    var nodes: [Node] = []
    var remove: [String] = []
    var edges: [Edge] = []
    var unlink: [Unlink] = []
    /// Pode reiniciar ou remover terminal em segundo plano. Segundo plano é
    /// tanto "esperando um vizinho" (inofensivo de interromper) quanto "um
    /// processo rodando" (não é) — o app não distingue, quem olha é o maestro,
    /// com `egeon peek`. Turno em curso não se força.
    var force = false
    /// Rearrumar o canvas (`MaestroLayout`). Ausente = só quando o plano cria
    /// ou remove terminal; `false` deixa como está; `true` rearruma mesmo sem
    /// mudança de time.
    var layout: Bool?

    var isEmpty: Bool {
        rules.isKeep && maxVisits.isKeep && nodes.isEmpty && remove.isEmpty
            && edges.isEmpty && unlink.isEmpty && layout != true
    }
}

// MARK: - Leitura

extension MaestroPlan: Decodable {
    /// Chave desconhecida é erro, e não silêncio: quem escreve isto é um modelo,
    /// e `"modle": "opus"` ignorado deixaria o nó no padrão sem ninguém saber.
    struct UnknownKeys: Error, CustomStringConvertible {
        let path: String
        let keys: [String]
        let expected: [String]
        var description: String {
            "\(path): campo(s) desconhecido(s) \(keys.map { "'\($0)'" }.joined(separator: ", "))"
                + " — aceitos: \(expected.joined(separator: ", "))"
        }
    }

    struct ParseError: Error, Equatable { let message: String }

    enum Keys: String, CodingKey, CaseIterable {
        case rules, maxVisits, nodes, remove, edges, unlink, force, layout
    }

    init(from decoder: Decoder) throws {
        try PlanKeys.check(decoder, Keys.self, path: "plano")
        let c = try decoder.container(keyedBy: Keys.self)
        rules = try c.field(String.self, .rules)
        maxVisits = try c.field(Int.self, .maxVisits)
        nodes = try c.decodeIfPresent([Node].self, forKey: .nodes) ?? []
        remove = try c.decodeIfPresent([String].self, forKey: .remove) ?? []
        edges = try c.decodeIfPresent([Edge].self, forKey: .edges) ?? []
        unlink = try c.decodeIfPresent([Unlink].self, forKey: .unlink) ?? []
        force = try c.decodeIfPresent(Bool.self, forKey: .force) ?? false
        layout = try c.decodeIfPresent(Bool.self, forKey: .layout)
    }

    /// Lê o corpo do `egeon plan`/`egeon apply`. O erro já vem em português e
    /// apontando o lugar, porque volta direto para o agente corrigir.
    static func parse(_ data: Data) -> Result<MaestroPlan, ParseError> {
        guard !data.isEmpty else { return .failure(ParseError(message: "plano vazio — mande o JSON no stdin")) }
        do {
            return .success(try JSONDecoder().decode(MaestroPlan.self, from: data))
        } catch let error as UnknownKeys {
            return .failure(ParseError(message: error.description))
        } catch let DecodingError.dataCorrupted(context) {
            return .failure(ParseError(message: "JSON inválido\(Self.where(context.codingPath)): "
                            + context.debugDescription))
        } catch let DecodingError.keyNotFound(key, context) {
            return .failure(ParseError(message: "falta '\(key.stringValue)'\(Self.where(context.codingPath))"))
        } catch let DecodingError.typeMismatch(_, context) {
            return .failure(ParseError(message: "tipo errado\(Self.where(context.codingPath)): "
                            + context.debugDescription))
        } catch let DecodingError.valueNotFound(_, context) {
            return .failure(ParseError(message: "valor nulo onde não pode\(Self.where(context.codingPath))"))
        } catch {
            return .failure(ParseError(message: "plano ilegível: \(error)"))
        }
    }

    private static func `where`(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else { return "" }
        let text = path.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        return " em \(text.hasPrefix(".") ? String(text.dropFirst()) : text)"
    }
}

extension MaestroPlan.Node: Decodable {
    /// `cmd` é poder de rodar comando sem o prompt de permissão do CLI do
    /// maestro: dado de propósito, porque terminal normal é parte da bancada
    /// (ADR-066). O portão é o `egeon apply` passar pela permissão do Bash.
    enum Keys: String, CodingKey, CaseIterable {
        case id, kind, cli, model, effort, ultracode, role, rules, cwd, config, cmd, frame
    }

    /// O que o `egeon bench` mostra e não se escreve: copiar um nó de lá para
    /// o plano não pode falhar por causa deles.
    enum ReadOnly: String, CodingKey, CaseIterable { case state, you, maestro }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        let extra = try decoder.container(keyedBy: ReadOnly.self)
        if extra.contains(.maestro), (try? extra.decode(Bool.self, forKey: .maestro)) == true {
            throw MaestroPlan.UnknownKeys(path: "nó '\(id)'", keys: ["maestro"],
                                          expected: ["— só o usuário faz um maestro, no formulário"])
        }
        try PlanKeys.check(decoder, Keys.self, path: "nó '\(id)'",
                           ignoring: ReadOnly.allCases.map(\.rawValue))
        kind = try c.decodeIfPresent(NodeKind.self, forKey: .kind)
        cli = try c.field(String.self, .cli)
        model = try c.field(String.self, .model)
        effort = try c.field(String.self, .effort)
        ultracode = try c.field(Bool.self, .ultracode)
        role = try c.field(String.self, .role)
        rules = try c.field(String.self, .rules)
        cwd = try c.field(String.self, .cwd)
        config = try c.field(String.self, .config)
        cmd = try c.field(String.self, .cmd)
        frame = try c.decodeIfPresent(MaestroPlan.Frame.self, forKey: .frame)
    }
}

extension MaestroPlan.Edge: Decodable {
    enum Keys: String, CodingKey, CaseIterable { case from, to, both, maxSends }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        try PlanKeys.check(decoder, Keys.self, path: "aresta \(from)→\(to)")
        both = try c.decodeIfPresent(Bool.self, forKey: .both) ?? false
        maxSends = try c.field(Int.self, .maxSends)
    }
}

extension MaestroPlan.Unlink: Decodable {
    enum Keys: String, CodingKey, CaseIterable { case from, to, both }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        try PlanKeys.check(decoder, Keys.self, path: "unlink \(from)→\(to)")
        both = try c.decodeIfPresent(Bool.self, forKey: .both) ?? false
    }
}

enum PlanKeys {
    struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    static func check<K: CodingKey & CaseIterable & RawRepresentable>(
        _ decoder: Decoder, _: K.Type, path: String, ignoring: [String] = []
    ) throws where K.RawValue == String {
        let present = try decoder.container(keyedBy: AnyKey.self).allKeys.map(\.stringValue)
            .filter { !ignoring.contains($0) }
        let known = K.allCases.map(\.rawValue)
        let unknown = present.filter { !known.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw MaestroPlan.UnknownKeys(path: path, keys: unknown, expected: known)
        }
    }
}

private extension KeyedDecodingContainer {
    func field<T: Decodable & Equatable>(_: T.Type, _ key: Key) throws -> PlanField<T> {
        guard contains(key) else { return .keep }
        if try decodeNil(forKey: key) { return .clear }
        return .set(try decode(T.self, forKey: key))
    }
}
