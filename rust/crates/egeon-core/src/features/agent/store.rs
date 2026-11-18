//! O `agents.json` do flavor: perfis de CLI por chave, com migração de campos
//! novos para arquivos escritos por versões anteriores.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use super::claude::profile::claude_code;
use super::model::{AgentProfile, AttentionConfig, IdleConfig, InjectConfig};
use crate::features::json_file::write_pretty;

pub type Profiles = BTreeMap<String, AgentProfile>;

pub fn config_path(home: &Path) -> PathBuf {
    home.join("agents.json")
}

/// O arquivo, ou os padrões (que são gravados). Arquivo ilegível ou vazio cai
/// nos padrões como no Swift.
pub fn load(home: &Path) -> Profiles {
    let file = config_path(home);
    if let Ok(bytes) = fs::read(&file)
        && let Ok(map) = crate::features::json_file::parse::<Profiles>(&bytes)
        && !map.is_empty()
    {
        return migrated(home, map);
    }
    let defaults = default_profiles();
    save(home, &defaults);
    defaults
}

pub fn save(home: &Path, profiles: &Profiles) {
    if let Err(error) = write_pretty(&config_path(home), profiles) {
        crate::log!("agents.json: {error}");
    }
}

pub fn default_profiles() -> Profiles {
    let mut codex = AgentProfile::new("Codex CLI", &["codex"]);
    codex.idle = Some(IdleConfig::default());
    codex.inject = Some(InjectConfig::default());
    codex.model = Some(vec!["--model".into(), "{model}".into()]);
    codex.models = Some(Vec::new());
    codex.attention = Some(AttentionConfig::default());
    codex.config_env = Some("CODEX_HOME".into());
    codex.config_glob = Some("~/.codex*".into());

    let mut opencode = AgentProfile::new("OpenCode", &["opencode"]);
    opencode.idle = Some(IdleConfig {
        strategy: "silence".into(),
        ms: 1200,
        ..IdleConfig::default()
    });
    opencode.inject = Some(InjectConfig::default());
    opencode.attention = Some(AttentionConfig::default());

    let mut gemini = AgentProfile::new("Gemini CLI", &["gemini"]);
    gemini.idle = Some(IdleConfig::default());
    gemini.inject = Some(InjectConfig::default());
    gemini.model = Some(vec!["--model".into(), "{model}".into()]);
    gemini.models = Some(Vec::new());
    gemini.attention = Some(AttentionConfig::default());

    BTreeMap::from([
        // O que é do Claude mora no submódulo `claude`; aqui só a chave.
        ("claude".to_owned(), claude_code()),
        ("codex".to_owned(), codex),
        ("opencode".to_owned(), opencode),
        ("gemini".to_owned(), gemini),
    ])
}

/// Preenche `$field` em perfil que não o declara E cujo comando é o que o padrão
/// conhece: quem trocou o comando pode ter trocado de binário, e anexar uma flag
/// a um CLI desconhecido faria o terminal morrer no arranque.
macro_rules! fill {
    ($map:expr, $updated:expr, $defaults:expr, $changed:expr, $field:ident, [$($also:ident),*]) => {
        for (key, profile) in $map.iter().filter(|(_, p)| p.$field.is_none()) {
            let Some(default) = $defaults.get(key) else { continue };
            if default.$field.is_none() || default.command != profile.command {
                continue;
            }
            if let Some(target) = $updated.get_mut(key) {
                target.$field = default.$field.clone();
                $(if profile.$also.is_none() { target.$also = default.$also.clone(); })*
            }
            $changed.push(format!("{key}.{}", stringify!($field)));
        }
    };
}

fn migrated(home: &Path, map: Profiles) -> Profiles {
    let defaults = default_profiles();
    let mut updated = map.clone();
    let mut changed: Vec<String> = Vec::new();

    fill!(map, updated, defaults, changed, system_prompt, []);
    // `new_session` é o par de `resume`, e sem ele o app não sabe CRIAR uma
    // conversa com id próprio — só retomar, que na estreia não existe.
    fill!(map, updated, defaults, changed, new_session, []);
    fill!(map, updated, defaults, changed, report_session, []);
    // `config_env` e `config_glob` descrevem a configuração DAQUELE CLI.
    fill!(map, updated, defaults, changed, config_env, []);
    fill!(map, updated, defaults, changed, config_glob, []);
    // `model`/`models` descrevem a flag DAQUELE CLI, como `resume`.
    fill!(map, updated, defaults, changed, model, [models]);

    // A primeira lista de fábrica saiu sem `fable`; quem ainda tem exatamente ela
    // ganha a atual. Lista editada à mão não é tocada.
    let first_list = ["opus", "sonnet", "haiku"].map(String::from).to_vec();
    for (key, profile) in &map {
        if profile.models.as_ref() != Some(&first_list) {
            continue;
        }
        let Some(default) = defaults.get(key) else {
            continue;
        };
        if default.command != profile.command {
            continue;
        }
        if let Some(target) = updated.get_mut(key) {
            target.models = default.models.clone();
        }
        changed.push(format!("{key}.models"));
    }

    fill!(map, updated, defaults, changed, effort, [efforts]);
    fill!(map, updated, defaults, changed, ultracode, [effort_env]);
    // `clear` é comando de barra DAQUELE CLI: mesma trava de comando.
    fill!(map, updated, defaults, changed, clear, []);

    // `attention` não depende de qual binário roda: som, limiar de silêncio e
    // marcador valem para qualquer CLI. Por isso aqui não vale a trava de
    // comando — e o campo é escrito para o usuário poder editá-lo.
    for (key, profile) in &map {
        if profile.attention.is_none() {
            if let Some(target) = updated.get_mut(key) {
                target.attention = Some(AttentionConfig::default());
            }
            changed.push(format!("{key}.attention"));
        }
    }

    if changed.is_empty() {
        return map;
    }
    save(home, &updated);
    crate::log!("agents.json: campos preenchidos — {}", changed.join(", "));
    updated
}
