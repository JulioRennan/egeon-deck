import Foundation

/// Quem usa cada app de desktop que o Egeon abriu (ADR-084), por bundle id.
///
/// Só app que o Egeon ABRIU é fechado: o que já estava aberto é seu, e um
/// `open` de agente nele só o traz para a frente — o processo não muda, e a
/// marca não chega. Dividido entre bancadas, quem fecha é o último a sair:
/// quem abriu entra pela marca; quem ainda usava quando ele saiu (conexão
/// viva, container) fica registrado aqui como herdeiro. Em `apps.json`, porque
/// o app fica de pé entre reinícios do Egeon.
struct AppClaims: Codable, Equatable {
    struct Entry: Codable, Equatable {
        /// Aberto por um terminal do Egeon.
        var launched = false
        var users: Set<String> = []
    }

    var apps: [String: Entry] = [:]

    /// Os apps a fechar quando `leaving` sai, e os usos deles esquecidos.
    ///
    /// `launchers` é quem a marca no processo do app aponta (bundle → nó): o
    /// app aberto antes do registro, ou por outra via, ainda é de quem o abriu.
    /// `live` são os nós de pé depois da saída; uso de nó morto não segura app.
    mutating func release(_ leaving: Set<String>, live: Set<String>,
                          launchers: [String: String]) -> [String] {
        var close: [String] = []
        for bundle in Set(apps.keys).union(launchers.keys) {
            var entry = apps[bundle] ?? Entry()
            if let launcher = launchers[bundle] {
                entry.launched = true
                entry.users.insert(launcher)
            }
            guard !entry.users.isDisjoint(with: leaving) else { continue }
            entry.users = entry.users.subtracting(leaving).intersection(live)
            if entry.users.isEmpty {
                apps[bundle] = nil
                if entry.launched { close.append(bundle) }
            } else {
                apps[bundle] = entry
            }
        }
        return close.sorted()
    }

    /// O nó que abriu o app, pelo ambiente do processo dele. Só vale para quem
    /// o launchd abriu como ESTE app: a janela do Docker Desktop é outro bundle,
    /// aberto pelo motor, e carrega a marca herdada — fechá-la derruba o Docker.
    static func opener(of bundle: String, environment: [String: String]) -> String? {
        guard environment[ProcessMark.bundleVariable] == bundle else { return nil }
        return ProcessMark.node(in: environment)
    }

    static var file: URL { Flavor.current.config("apps.json") }

    static func load() -> AppClaims {
        guard let data = try? Data(contentsOf: file),
              let claims = try? JSONDecoder().decode(AppClaims.self, from: data) else { return AppClaims() }
        return claims
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(self).write(to: Self.file, options: .atomic)
    }
}

/// Os sockets unix de cada processo, da saída `lsof -U -F pdn`: o endereço do
/// próprio socket (`d`) e, se conectado, o do outro lado (`n->0x…`). É como se
/// vê que um terminal de outra bancada ainda fala com o app — o `docker compose
/// up` preso ao socket do Docker — sem ele ter aberto o app.
struct SocketTable: Equatable {
    var own: [Int32: Set<String>] = [:]
    var peers: [Int32: Set<String>] = [:]

    init(lsof output: String) {
        var pid: Int32 = 0
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "d": own[pid, default: []].insert(value)
            case "n" where value.hasPrefix("->0x"):
                peers[pid, default: []].insert(String(value.dropFirst(2)))
            default: break
            }
        }
    }

    /// Dos `candidates`, os que têm socket ligado a algum socket de `app`.
    func connected(_ candidates: Set<Int32>, to app: Set<Int32>) -> Set<Int32> {
        let theirs = app.reduce(into: Set<String>()) { $0.formUnion(own[$1] ?? []) }
        return candidates.filter { !(peers[$0] ?? []).isDisjoint(with: theirs) }
    }
}
