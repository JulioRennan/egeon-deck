//! O perfil de fábrica do Claude Code — todo o conhecimento sobre ELE num lugar
//! só: as flags de conversa, o arquivo de settings dos ganchos e o diretório de
//! config.

use crate::features::agent::model::{AgentProfile, AttentionConfig, IdleConfig, InjectConfig};

fn args(list: &[&str]) -> Option<Vec<String>> {
    Some(list.iter().map(|s| (*s).to_owned()).collect())
}

pub fn claude_code() -> AgentProfile {
    // `--append-system-prompt` vale em bancada interativa, não só com `--print`,
    // e funciona com login normal — não é exclusivo de quem usa API key.
    AgentProfile {
        display_name: "Claude Code".to_owned(),
        command: vec!["claude".to_owned()],
        idle: Some(IdleConfig::default()),
        inject: Some(InjectConfig::default()),
        resume: args(&["--resume", "{sessionId}"]),
        new_session: args(&["--session-id", "{sessionId}"]),
        report_session: args(&["--settings", "{file}"]),
        system_prompt: args(&["--append-system-prompt", "{prompt}"]),
        clear: Some("/clear".to_owned()),
        // Apelidos que o CLI resolve para a versão corrente de cada família.
        // Também vale nome completo (`claude-fable-5`) e sufixo `[1m]`: é só
        // escrever no agents.json.
        model: args(&["--model", "{model}"]),
        models: args(&["fable", "opus", "sonnet", "haiku", "opusplan"]),
        // Os níveis do `claude --help` — o teto. Quais valem para cada modelo vem
        // do catálogo lido do binário.
        effort: args(&["--effort", "{effort}"]),
        efforts: args(&["low", "medium", "high", "xhigh", "max"]),
        // `--effort ultracode` liga o modo e ocupa a flag; o nível segue pela
        // variável, que o CLI lê no arranque.
        ultracode: args(&["--effort", "ultracode"]),
        effort_env: Some("CLAUDE_CODE_EFFORT_LEVEL".to_owned()),
        attention: Some(AttentionConfig::default()),
        config_env: Some("CLAUDE_CONFIG_DIR".to_owned()),
        config_glob: Some("~/.claude*".to_owned()),
        ..AgentProfile::default()
    }
}
