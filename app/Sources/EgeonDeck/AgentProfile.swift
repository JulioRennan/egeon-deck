import Foundation

/// Como saber que o agente terminou de trabalhar.
/// Só existe `silence` hoje: TUI de agente redesenha a tela com ANSI, spinner e
/// movimento de cursor, então parsear saída quebra a cada release do CLI.
/// Silêncio no pty é barato e estável (ADR-008).
struct IdleConfig: Codable {
    var strategy: String = "silence"
    var ms: Int = 1500

    /// Tempo mínimo desde o start do processo antes de considerar a sessão
    /// utilizável. Sem isso, uma pausa durante o boot da TUI passa por
    /// ociosidade e o prompt é entregue antes de existir quem o leia — some
    /// sem deixar rastro.
    var warmupMs: Int = 4000
}

/// Como entregar um prompt na sessão.
struct InjectConfig: Codable {
    /// `bracketed-paste` para TUI (senão cada \n vira um submit separado),
    /// `plain` para CLI que lê linha a linha.
    var mode: String = "bracketed-paste"
    var submit: String = "\r"

    /// Pausa entre colar e apertar Enter. TUI em Ink (Claude Code) processa a
    /// entrada de forma assíncrona: o `\r` enviado no mesmo instante do fim do
    /// paste é engolido e o prompt fica parado na caixa de input.
    var submitDelayMs: Int = 150

    var submitDelay: TimeInterval { Double(submitDelayMs) / 1000.0 }
}

// MARK: - Decode tolerante a chave faltando
//
// O `Decodable` sintetizado NÃO usa o valor padrão da propriedade: chave
// ausente é `keyNotFound` e o decode inteiro joga. Como `AgentStore.load` cai
// no `try?` e regrava os padrões, um agents.json editado à mão com uma chave a
// menos era apagado e substituído sem aviso — exatamente o oposto de "trocar de
// agente é editar JSON" (ADR-009).
//
// Os inits vão em extensão, e não no corpo do struct: declarar `init(from:)`
// dentro do corpo apaga o init memberwise, que é como os padrões são montados
// no código.

extension IdleConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = IdleConfig()
        strategy = try container.decodeIfPresent(String.self, forKey: .strategy) ?? fallback.strategy
        ms = try container.decodeIfPresent(Int.self, forKey: .ms) ?? fallback.ms
        warmupMs = try container.decodeIfPresent(Int.self, forKey: .warmupMs) ?? fallback.warmupMs
    }
}

extension InjectConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = InjectConfig()
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? fallback.mode
        submit = try container.decodeIfPresent(String.self, forKey: .submit) ?? fallback.submit
        submitDelayMs = try container.decodeIfPresent(Int.self, forKey: .submitDelayMs)
            ?? fallback.submitDelayMs
    }
}

/// Protocolo de fim de turno: o agente termina cada resposta com um marcador
/// dizendo se acabou ou se depende de você.
///
/// É o oposto de parsear a TUI. Em vez de adivinhar o desenho do CLI — que muda
/// a cada release —, a gente pede ao modelo um sinal que nós mesmos escolhemos.
/// O texto vai no system prompt, então não gasta turno nem aparece na conversa
/// (ADR-011).
struct MarkerConfig: Codable {
    var enabled: Bool = true
    /// Escrito pelo agente quando terminou e não depende de nada.
    var done: String = "[[ED:ok]]"
    /// Escrito quando ele parou porque depende de uma resposta sua.
    var ask: String = "[[ED:ask]]"
    /// Instrução anexada ao system prompt. `{done}` e `{ask}` são substituídos
    /// pelos marcadores acima.
    var instruction: String = MarkerConfig.defaultInstruction

    /// ASCII curto e numa linha só de propósito: marcador comprido é quebrado
    /// pela TUI quando a janela é estreita, e um marcador partido em duas
    /// linhas não casa mais.
    static let defaultInstruction = """
        Protocolo Egeon: termine TODA resposta com um marcador sozinho na \
        última linha, sem nada depois dele.
        {done} — terminei e não dependo de você.
        {ask} — parei e dependo de uma resposta sua: dúvida, escolha, permissão \
        ou informação que falta.
        Se você fez uma pergunta ao usuário, o marcador é {ask}. Um marcador só, \
        sempre por último.
        """

    var resolvedInstruction: String {
        instruction
            .replacingOccurrences(of: "{done}", with: done)
            .replacingOccurrences(of: "{ask}", with: ask)
    }
}

/// Como o terminal avisa que parou e precisa de você.
struct AttentionConfig: Codable {
    /// Som tocado na transição para "precisa de você". Nome de
    /// `/System/Library/Sounds` ou `~/Library/Sounds`. Vazio ou `null` desliga o
    /// som e mantém o aviso visual.
    ///
    /// `Tink` é o mais curto do catálogo do sistema (~0,2 s) e o que menos
    /// interrompe. Outros discretos: `Pop`, `Purr`. `Glass` e `Hero` chamam
    /// atenção demais para algo que dispara o dia inteiro.
    var sound: String? = "Tink"

    /// 0…1, relativo ao volume de alerta do sistema.
    ///
    /// Trocar de som muda o timbre; o volume é o que de fato faz o aviso ser
    /// discreto. `Tink` em 0,3 é um toque de copo do outro lado da sala:
    /// perceptível se você estiver por perto, ignorável se estiver concentrado.
    var volume: Double = 0.3

    /// Rajada mínima de saída para o silêncio seguinte valer um aviso.
    ///
    /// Sem isso qualquer respiro conta como "terminou": a TUI redesenhando um
    /// spinner, o eco de uma tecla, um `clear`. Só vale como desempate — quando
    /// o agente escreve o marcador, o sinal é explícito e o limiar não entra.
    var minWorkMs: Int = 2000

    var marker: MarkerConfig? = MarkerConfig()

    /// Regex sobre as últimas linhas visíveis, tentadas quando não há marcador
    /// na tela.
    ///
    /// Existe para o diálogo de permissão do PRÓPRIO CLI (`Do you want to
    /// proceed?`, `❯ 1. Yes`): ele é desenhado pelo programa, não é mensagem do
    /// modelo, e por isso nunca vai carregar marcador nenhum. Vazio por padrão
    /// — casar desenho de TUI é manutenção sua a cada release (ADR-011).
    var patterns: [String] = []

    var minWork: TimeInterval { Double(minWorkMs) / 1000.0 }

    /// Marcador ativo, ou nil quando desligado.
    var activeMarker: MarkerConfig? {
        guard let marker, marker.enabled else { return nil }
        return marker
    }
}

extension MarkerConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MarkerConfig()
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        done = try container.decodeIfPresent(String.self, forKey: .done) ?? fallback.done
        ask = try container.decodeIfPresent(String.self, forKey: .ask) ?? fallback.ask
        instruction = try container.decodeIfPresent(String.self, forKey: .instruction)
            ?? fallback.instruction
    }
}

extension AttentionConfig {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AttentionConfig()
        // `sound` é Optional com padrão não-nulo: `decodeIfPresent` devolve nil
        // tanto para chave ausente quanto para `"sound": null`, e são coisas
        // diferentes — ausente herda o padrão, nulo explícito desliga o som.
        sound = container.contains(.sound)
            ? try container.decodeIfPresent(String.self, forKey: .sound)
            : fallback.sound
        volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? fallback.volume
        minWorkMs = try container.decodeIfPresent(Int.self, forKey: .minWorkMs)
            ?? fallback.minWorkMs
        marker = container.contains(.marker)
            ? try container.decodeIfPresent(MarkerConfig.self, forKey: .marker)
            : fallback.marker
        patterns = try container.decodeIfPresent([String].self, forKey: .patterns)
            ?? fallback.patterns
    }
}

/// Perfil de um agente CLI. Nada no resto do código conhece "Claude Code" —
/// trocar de agente é editar o `agents.json` do flavor (ADR-009).
struct AgentProfile: Codable {
    var displayName: String
    var command: [String]
    var idle: IdleConfig?
    var inject: InjectConfig?
    /// Como retomar uma conversa existente. `{sessionId}` é substituído.
    var resume: [String]?

    /// Como criar a conversa com um id que NÓS escolhemos. `{sessionId}` é
    /// substituído.
    ///
    /// Os dois flags são necessários, e não é redundância: medido no Claude Code
    /// 2.1.229, `--session-id` num id que já existe responde
    /// `Session ID ... is already in use` e sai com 1. Criar e retomar são
    /// verbos diferentes para o CLI, então são dois campos aqui.
    var newSession: [String]?

    /// Como pedir ao CLI que avise qual conversa está aberta. `{file}` é
    /// substituído pelo caminho do arquivo de hooks que o app escreve.
    ///
    /// Sem isto o app só conhece a conversa que ele mesmo criou: `/resume`,
    /// `/clear` ou fork feitos por você na TUI ficam invisíveis, e o arranque
    /// seguinte desfaz a sua escolha.
    var reportSession: [String]?

    /// Como passar o papel do terminal já no arranque, com `{prompt}`
    /// substituído pelo texto. Declarado por perfil porque a flag muda de CLI
    /// para CLI — e alguns não têm nenhuma.
    ///
    /// Vale mais que injetar o papel como primeira mensagem: não gasta um turno,
    /// não aparece na conversa e não se dilui depois de vinte mensagens.
    var systemPrompt: [String]?

    var attention: AttentionConfig?

    /// Variáveis de ambiente do processo deste agente, por cima do que o app já
    /// entrega.
    ///
    /// Existe porque a configuração de um CLI costuma morar no ambiente, e não
    /// na linha de comando: `CLAUDE_CONFIG_DIR` é o caso do dia a dia — o mesmo
    /// `claude`, com o conjunto de plugins, MCP e settings do trabalho ou o
    /// pessoal. Dois perfis apontando para o mesmo binário e diferindo só aqui
    /// dão a escolha no popup de CLI, na hora de criar o terminal.
    ///
    /// Ambiente e não `cmd` porque `cmd` com prefixo `VAR=valor` deixa de casar
    /// com `runsOwnBinary`, e aí o nó perde system prompt, gancho de conversa e
    /// retomada de sessão sem dizer nada.
    var env: [String: String]?

    /// A variável com que este CLI troca de conjunto de configuração — plugins,
    /// MCP, settings, credenciais.
    ///
    /// O nome é da CLI, não nosso, e muda de uma para outra: `CLAUDE_CONFIG_DIR`
    /// no Claude Code, `CODEX_HOME` no Codex. Por isso quem declara é o perfil.
    ///
    /// É o que deixa escolher a configuração no formulário do terminal em vez de
    /// editar JSON: o app já sabe qual chave escrever no ambiente.
    var configEnv: String?

    /// Onde as configurações desta CLI ficam, para o formulário oferecer as que
    /// você já tem em vez de pedir que digite o caminho.
    ///
    /// Um `*` no fim, e só ali: `~/.claude*` acha `.claude`, `.claude-trabalho`,
    /// `.claude-pessoal`. Não é glob de verdade — é o bastante para o formato que
    /// toda CLI usa (uma pasta escondida no home) e não convida a inventar
    /// padrão que o app teria de interpretar.
    var configGlob: String?

    /// As configurações desta CLI que existem no disco agora.
    ///
    /// Consultado a cada abertura do formulário: criar um `~/.claude-x` no
    /// terminal e vê-lo na lista sem reiniciar o app é o comportamento esperado.
    var discoveredConfigs: [URL] {
        guard let configGlob, configGlob.hasSuffix("*") else { return [] }

        let pattern = String(configGlob.dropLast())
        let expanded = (pattern as NSString).expandingTildeInPath
        let directory = (expanded as NSString).deletingLastPathComponent
        let prefix = (expanded as NSString).lastPathComponent

        let fm = FileManager.default
        let found = (try? fm.contentsOfDirectory(atPath: directory)) ?? []
        return found
            .filter { $0.hasPrefix(prefix) }
            .map { URL(fileURLWithPath: directory).appendingPathComponent($0) }
            // Só diretório: `~/.claude*` casa também com o `~/.claude.json`, que
            // é estado do CLI e não uma configuração para onde apontar.
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// `env` com `~` e `$HOME` resolvidos.
    ///
    /// O ambiente vai montado direto para o processo filho: ninguém expande til
    /// no caminho, e um `CLAUDE_CONFIG_DIR=~/.claude-trabalho` literal faz o CLI
    /// criar uma pasta chamada `~` dentro do cwd do terminal.
    var resolvedEnvironment: [String: String] {
        (env ?? [:]).mapValues { value in
            let home = NSHomeDirectory()
            var resolved = value.replacingOccurrences(of: "$HOME", with: home)
            if resolved == "~" { resolved = home }
            if resolved.hasPrefix("~/") { resolved = home + resolved.dropFirst(1) }
            return resolved
        }
    }

    var idleInterval: TimeInterval { Double(idle?.ms ?? 1500) / 1000.0 }
    var warmupInterval: TimeInterval { Double(idle?.warmupMs ?? 4000) / 1000.0 }
    var injectConfig: InjectConfig { inject ?? InjectConfig() }
    var attentionConfig: AttentionConfig { attention ?? AttentionConfig() }

    /// O que entra no system prompt do agente: o protocolo de marcador e o papel
    /// deste terminal, nessa ordem. Nil quando não há nem um nem outro.
    ///
    /// O protocolo vem primeiro porque é regra de formato e vale para tudo; o
    /// papel é o assunto, e assunto depois de regra é o que o modelo lê melhor.
    func systemPromptText(role: String?, catalog: String? = nil) -> String? {
        var parts: [String] = []
        if let marker = attentionConfig.activeMarker { parts.append(marker.resolvedInstruction) }
        if let catalog, !catalog.isEmpty { parts.append(catalog) }
        if let role, !role.isEmpty { parts.append(role) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// Argumentos de system prompt, prontos para a linha de comando. Nil quando
    /// o CLI não sabe recebê-lo no arranque — aí o texto vira mensagem.
    func systemPromptArguments(for prompt: String) -> [String]? {
        guard let systemPrompt, !systemPrompt.isEmpty else { return nil }
        return systemPrompt.map { $0.replacingOccurrences(of: "{prompt}", with: prompt) }
    }

    /// Argumentos de sessão prontos para a linha de comando, com `{sessionId}`
    /// substituído. Nil quando o perfil não declara a forma pedida.
    func sessionArguments(_ template: [String]?, id: String) -> [String]? {
        guard let template, !template.isEmpty else { return nil }
        return template.map { $0.replacingOccurrences(of: "{sessionId}", with: id) }
    }

    /// O CLI sabe retomar conversa por id que escolhemos?
    var keepsConversation: Bool { resume != nil && newSession != nil }

    /// Argumentos que instalam o gancho de relato. Nil quando o perfil não o
    /// declara — aí o app fica só com a conversa que ele mesmo criou.
    func reportArguments(hookFile: String) -> [String]? {
        guard let reportSession, !reportSession.isEmpty else { return nil }
        return reportSession.map { $0.replacingOccurrences(of: "{file}", with: hookFile) }
    }

    /// Esta linha de comando ainda é o binário que o perfil declara?
    ///
    /// Quem trocou o `cmd` do nó pode ter trocado de programa, e anexar
    /// `--append-system-prompt` a outra coisa mata o terminal no arranque.
    func runsOwnBinary(_ command: String) -> Bool {
        guard let binary = self.command.first, !binary.isEmpty else { return false }
        return command == binary || command.hasPrefix(binary + " ")
    }
}

enum AgentStore {
    static let configURL = URL(fileURLWithPath:
        Flavor.current.config("agents.json").path)

    static func load() -> [String: AgentProfile] {
        if let data = try? Data(contentsOf: configURL),
           let map = try? JSONDecoder().decode([String: AgentProfile].self, from: data),
           !map.isEmpty {
            return migrated(map)
        }
        let defaults = defaultProfiles()
        save(defaults)
        return defaults
    }

    /// Preenche campos novos em arquivos escritos por versões anteriores.
    ///
    /// Só toca em perfil que não declara o campo E cujo comando é o que o padrão
    /// conhece: quem trocou o comando pode ter trocado de binário, e anexar uma
    /// flag a um CLI desconhecido faria o terminal morrer no arranque.
    private static func migrated(_ map: [String: AgentProfile]) -> [String: AgentProfile] {
        let defaults = defaultProfiles()
        var updated = map
        var changed: [String] = []

        for (key, profile) in map where profile.systemPrompt == nil {
            guard let padrão = defaults[key], padrão.systemPrompt != nil,
                  padrão.command == profile.command else { continue }
            updated[key]?.systemPrompt = padrão.systemPrompt
            changed.append("\(key).systemPrompt")
        }

        // `newSession` é o par de `resume`, e sem ele o app não sabe CRIAR uma
        // conversa com id próprio — só retomar, que na estreia não existe. A
        // mesma trava de comando vale: anexar `--session-id` a um binário que não
        // conhece a flag mata o terminal no arranque.
        for (key, profile) in map where profile.newSession == nil {
            guard let padrão = defaults[key], padrão.newSession != nil,
                  padrão.command == profile.command else { continue }
            updated[key]?.newSession = padrão.newSession
            changed.append("\(key).newSession")
        }

        for (key, profile) in map where profile.reportSession == nil {
            guard let padrão = defaults[key], padrão.reportSession != nil,
                  padrão.command == profile.command else { continue }
            updated[key]?.reportSession = padrão.reportSession
            changed.append("\(key).reportSession")
        }

        // `configEnv` e `configGlob` descrevem a configuração DAQUELE CLI, então
        // vale a mesma trava: comando trocado pode ser outro programa, e oferecer
        // a variável errada faria o formulário montar uma escolha que não
        // configura nada.
        for (key, profile) in map where profile.configEnv == nil {
            guard let padrão = defaults[key], padrão.configEnv != nil,
                  padrão.command == profile.command else { continue }
            updated[key]?.configEnv = padrão.configEnv
            changed.append("\(key).configEnv")
        }

        for (key, profile) in map where profile.configGlob == nil {
            guard let padrão = defaults[key], padrão.configGlob != nil,
                  padrão.command == profile.command else { continue }
            updated[key]?.configGlob = padrão.configGlob
            changed.append("\(key).configGlob")
        }

        // `attention` não depende de qual binário roda: som, limiar de silêncio
        // e marcador valem para qualquer CLI. Por isso aqui não vale a trava de
        // comando de cima — e o campo é escrito para você poder editá-lo.
        for (key, profile) in map where profile.attention == nil {
            updated[key]?.attention = AttentionConfig()
            changed.append("\(key).attention")
        }

        guard !changed.isEmpty else { return map }
        save(updated)
        Log.write("agents.json: campos preenchidos — \(changed.joined(separator: ", "))")
        return updated
    }

    static func save(_ profiles: [String: AgentProfile]) {
        try? FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(profiles).write(to: configURL)
    }

    private static func defaultProfiles() -> [String: AgentProfile] {
        [
            // `--append-system-prompt` vale em sessão interativa, não só com
            // `--print`, e funciona com login normal — não é exclusivo de quem
            // usa API key. Verificado no help da 2.1.228, na referência de CLI e
            // executando.
            "claude": AgentProfile(
                displayName: "Claude Code", command: ["claude"],
                idle: IdleConfig(), inject: InjectConfig(),
                resume: ["--resume", "{sessionId}"],
                newSession: ["--session-id", "{sessionId}"],
                reportSession: ["--settings", "{file}"],
                systemPrompt: ["--append-system-prompt", "{prompt}"],
                attention: AttentionConfig(),
                configEnv: "CLAUDE_CONFIG_DIR", configGlob: "~/.claude*"),
            "codex": AgentProfile(
                displayName: "Codex CLI", command: ["codex"],
                idle: IdleConfig(), inject: InjectConfig(), resume: nil,
                attention: AttentionConfig(),
                configEnv: "CODEX_HOME", configGlob: "~/.codex*"),
            "opencode": AgentProfile(
                displayName: "OpenCode", command: ["opencode"],
                idle: IdleConfig(strategy: "silence", ms: 1200),
                inject: InjectConfig(), resume: nil,
                attention: AttentionConfig()),
            "gemini": AgentProfile(
                displayName: "Gemini CLI", command: ["gemini"],
                idle: IdleConfig(), inject: InjectConfig(), resume: nil,
                attention: AttentionConfig())
        ]
    }
}
