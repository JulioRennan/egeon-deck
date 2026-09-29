/// O perfil de fábrica do Claude Code — todo o conhecimento sobre ELE num
/// lugar só: as flags de conversa, o arquivo de settings dos ganchos e o
/// diretório de config.
///
/// Os outros CLIs continuam inline no `AgentStore.defaultProfiles`: nenhum tem
/// integração além do comando. Quando um ganhar — gancho, resume, adapter — ele
/// ganha um submódulo como este.
extension AgentProfile {
    static var claudeCode: AgentProfile {
        // `--append-system-prompt` vale em bancada interativa, não só com
        // `--print`, e funciona com login normal — não é exclusivo de quem
        // usa API key. Verificado no help da 2.1.228, na referência de CLI e
        // executando.
        AgentProfile(
            displayName: "Claude Code", command: ["claude"],
            idle: IdleConfig(), inject: InjectConfig(),
            resume: ["--resume", "{sessionId}"],
            newSession: ["--session-id", "{sessionId}"],
            reportSession: ["--settings", "{file}"],
            systemPrompt: ["--append-system-prompt", "{prompt}"],
            clear: "/clear",
            // Apelidos que o CLI resolve para a versão corrente de cada família —
            // os que o `claude --help` cita (fable, opus, sonnet) mais os que o
            // binário aceita (haiku, opusplan). Também vale nome completo
            // (`claude-fable-5`) e sufixo `[1m]`: é só escrever no agents.json.
            model: ["--model", "{model}"],
            models: ["fable", "opus", "sonnet", "haiku", "opusplan"],
            // Os níveis do `claude --help` (2.1.284) — o teto. Quais valem para
            // cada modelo vem do catálogo lido do binário (`ClaudeModelCatalog`).
            effort: ["--effort", "{effort}"],
            efforts: ["low", "medium", "high", "xhigh", "max"],
            // `--effort ultracode` liga o modo e ocupa a flag; o nível segue pela
            // variável, que o CLI lê no arranque (2.1.285).
            ultracode: ["--effort", "ultracode"],
            effortEnv: "CLAUDE_CODE_EFFORT_LEVEL",
            attention: AttentionConfig(),
            configEnv: "CLAUDE_CONFIG_DIR", configGlob: "~/.claude*")
    }
}
