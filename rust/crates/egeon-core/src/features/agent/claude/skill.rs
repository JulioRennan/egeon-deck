//! A skill que ensina o Claude Code a usar os vizinhos da bancada.
//!
//! O catálogo do system prompt diz o que o `egeon` faz, e não basta: quando o
//! usuário escreve "pede pro revisor olhar isso" ou "monta um time", o que
//! decide o caminho é a DESCRIÇÃO de uma ferramenta, não prosa que entrou no
//! prompt há vinte mensagens. Sem uma skill, a única descrição que casa com
//! essas frases é a do subagente do próprio CLI — e o agente spawna um subagente
//! invisível em vez de falar com o terminal ao lado (ADR-054).
//!
//! Skill é **por configuração do CLI**, e uma máquina tem várias: `~/.claude`,
//! `~/.claude-agro`, a que cada nó escolhe no formulário. Então ela é escrita no
//! root de CADA base path que existe no disco.
//!
//! É a exceção à regra de não escrever na config do usuário (os ganchos vão por
//! `--settings`): não há flag que entregue skill de fora. Uma pasta só, com nome
//! nosso, reescrita a cada arranque; nada mais na config é tocado (ADR-054).

use std::fs;
use std::path::{Path, PathBuf};

use crate::features::agent::model::{AgentProfile, expand_tilde};

/// O nome da pasta é o nome da skill: é dele que sai o `/egeon`.
pub const NAME: &str = "egeon";

const BODY: &str = include_str!("assets/egeon-skill.md");

/// Uma skill publicada: nome da pasta e o texto do `SKILL.md`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PublishedSkill {
    pub name: String,
    pub body: String,
}

/// Onde o CLI procura dentro de um base path.
pub fn skill_file(config: &Path, skill: &str) -> PathBuf {
    config.join("skills").join(skill).join("SKILL.md")
}

/// `user-invocable: false` porque isto não é um comando que o usuário digita: é
/// o que o agente precisa saber quando o usuário falar em outro agente.
/// `when_to_use` carrega as frases de gatilho — é o campo que o CLI lê para
/// decidir.
pub fn body() -> &'static str {
    BODY.trim_end_matches('\n')
}

/// As skills que o app publica: a dos vizinhos e o manual do maestro (ADR-066).
/// Vão as duas para toda configuração — a do maestro diz logo no começo que só
/// vale para o terminal que o usuário marcou.
pub fn published(maestro: &PublishedSkill) -> Vec<PublishedSkill> {
    vec![
        PublishedSkill {
            name: NAME.to_owned(),
            body: body().to_owned(),
        },
        maestro.clone(),
    ]
}

/// As configurações do Claude Code que existem agora: as do padrão `~/.claude*`
/// (o mesmo `config_glob` que o formulário do nó oferece) mais a do ambiente,
/// que pode estar fora dele. `environment` é o valor da variável de
/// configuração no ambiente do app.
pub fn config_directories(
    profile: &AgentProfile,
    home: &Path,
    environment: impl Fn(&str) -> Option<String>,
) -> Vec<PathBuf> {
    let mut out = profile.discovered_configs(home);
    let named = profile
        .config_env
        .as_deref()
        .and_then(environment)
        .filter(|n| !n.is_empty());
    if let Some(named) = named {
        let url = expand_tilde(&named, home);
        if !out.contains(&url) {
            out.push(url);
        }
    }
    out
}

/// Escrita a cada arranque, como o `bin/egeon` e o `claude-hooks.json`: o texto
/// acompanha a versão do app que subiu, não o que ficou no disco. Devolve onde
/// escreveu. `legacy_folder` é a pasta nossa da primeira tentativa (a skill
/// entregue por `--add-dir`): deixá-la é ter duas cópias da mesma skill em
/// disco, e um dia elas divergem.
pub fn install(
    configs: &[PathBuf],
    skills: &[PublishedSkill],
    legacy_folder: Option<&Path>,
) -> Vec<PathBuf> {
    if let Some(legacy) = legacy_folder {
        let _ = fs::remove_dir_all(legacy);
    }
    let mut written = Vec::new();
    for config in configs {
        for skill in skills {
            let file = skill_file(config, &skill.name);
            let result = file
                .parent()
                .map_or(Ok(()), fs::create_dir_all)
                .and_then(|()| super::write_atomic(&file, skill.body.as_bytes()));
            match result {
                Ok(()) => written.push(file),
                Err(error) => {
                    crate::log!("skill: não consegui escrever {} — {error}", file.display())
                }
            }
        }
    }
    written
}
