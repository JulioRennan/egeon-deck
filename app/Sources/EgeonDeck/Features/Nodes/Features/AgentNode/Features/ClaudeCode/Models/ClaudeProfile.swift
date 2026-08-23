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
            attention: AttentionConfig(),
            configEnv: "CLAUDE_CONFIG_DIR", configGlob: "~/.claude*")
    }
}
