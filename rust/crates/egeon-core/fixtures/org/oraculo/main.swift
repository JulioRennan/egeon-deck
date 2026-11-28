// O oráculo da persistência: lê cada arquivo de `entrada/` com o código REAL
// do Swift (os modelos de legado/, copiados sem alteração na compilação) e
// grava o que o Swift gravaria, em `esperado/`. Os testes do Rust comparam a
// leitura e a gravação deles com isto.
//
// Uso: oraculo <pasta com workbenches/ sessions/ workspaces/ components/
//               templates/> <pasta de saída>
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("uso: oraculo <entrada> <saida>\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let fm = FileManager.default

func files(_ sub: String) -> [URL] {
    let dir = input.appendingPathComponent(sub)
    let all = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    return all.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
}

func write<T: Encodable>(_ value: T, sub: String, name: String) throws {
    let dir = output.appendingPathComponent(sub)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: dir.appendingPathComponent(name))
}

let missing = URL(fileURLWithPath: "/nao-existe/\(UUID().uuidString)")

do {
    // O arranque do app: WorkbenchStore.load e depois assignMissing.
    for file in files("workbenches") {
        var list = WorkbenchStore.load(from: file, legacy: missing)
        WorkbenchColor.assignMissing(&list)
        try write(list, sub: "workbenches", name: file.lastPathComponent)
    }
    // O sessions.json antigo só é lido quando o novo nunca existiu.
    for file in files("sessions") {
        var list = WorkbenchStore.load(from: missing, legacy: file)
        WorkbenchColor.assignMissing(&list)
        try write(list, sub: "sessions", name: file.lastPathComponent)
    }
    // WorkspaceStore.load, com o caminho de entrada (o dele é fixo).
    for file in files("workspaces") {
        let data = try Data(contentsOf: file)
        let list = (try? JSONDecoder().decode([WorkspaceConfig].self, from: data)) ?? []
        try write(list, sub: "workspaces", name: file.lastPathComponent)
    }
    // NodeTemplateStore.load.
    for file in files("components") {
        let data = try Data(contentsOf: file)
        let map = (try? JSONDecoder().decode([String: Retirable<NodeTemplate>].self, from: data))?
            .compactMapValues(\.value) ?? [:]
        try write(map, sub: "components", name: file.lastPathComponent)
    }
    // WorkbenchTemplateStore.load.
    for file in files("templates") {
        let data = try Data(contentsOf: file)
        let map = (try? JSONDecoder().decode([String: WorkbenchTemplate].self, from: data)) ?? [:]
        try write(map, sub: "templates", name: file.lastPathComponent)
    }
    // WorkbenchClocks.clock(for:): o JSON do clock.json, com a data como o
    // `JSONEncoder` a grava.
    for file in files("clocks") {
        let data = try Data(contentsOf: file)
        let clock = (try? JSONDecoder().decode(WorkbenchClock.self, from: data)) ?? WorkbenchClock()
        try write(clock, sub: "clocks", name: file.lastPathComponent)
    }
    // O que o app põe na linha de comando e no system prompt de cada nó.
    let agents = AgentStore.load()
    try write(agents, sub: "perfis", name: "agents.json")
    ShellHook.install()
    let zsh = output.appendingPathComponent("zsh")
    try fm.createDirectory(at: zsh, withIntermediateDirectories: true)
    for name in [".zshenv", ".zprofile", ".zlogin", ".zshrc"] {
        try fm.copyItem(at: ShellHook.directory.appendingPathComponent(name),
                        to: zsh.appendingPathComponent(name))
    }
    struct LaunchCase: Decodable {
        var node: NodeConfig
        var profile: String?
        var rules: String?
    }
    struct LaunchResult: Encodable {
        var command: String
        var prompt: String?
        var hooked: Bool
        var catalog: String?
        var rules: String?
    }
    for file in files("launch") {
        let data = try Data(contentsOf: file)
        let spec = try JSONDecoder().decode(LaunchCase.self, from: data)
        let profile = spec.profile.flatMap { agents[$0] }
        let config = WorkbenchConfig(name: "w", path: "/t", nodes: [spec.node])
        let catalog = Launch.catalog(for: spec.node, in: config, agents: agents)
        let rules = AgentRules.block(workbench: spec.rules, node: spec.node.effectiveRules)
        let plan = Launch.launchPlan(for: spec.node, profile: profile, catalog: catalog, rules: rules)
        try write(LaunchResult(command: plan.command, prompt: plan.promptToInject,
                               hooked: plan.hooked, catalog: catalog, rules: rules),
                  sub: "launch", name: file.lastPathComponent)
    }
} catch {
    FileHandle.standardError.write(Data("erro: \(error)\n".utf8))
    exit(1)
}
