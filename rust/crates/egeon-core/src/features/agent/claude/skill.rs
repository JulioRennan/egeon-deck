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

use std::borrow::Cow;
use std::fs;
use std::path::{Path, PathBuf};

use crate::features::agent::model::{AgentProfile, expand_tilde};
use crate::features::terminal::shell::ShellSyntax;

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

const POSIX_MESSAGES: &str = "    egeon send <endereço> <<'MB'    manda o texto para ele
    (o que você quer dizer)
    MB
    egeon trace <<'MB'              registra na trilha da bancada
    pedido: … — entrega: …
    MB
";

/// O padrão do PowerShell 5.1 para o que vai a um programa pelo pipe é
/// ASCII, que troca acento por `?`; o `'@` que fecha o here-string só vale no
/// começo da linha, por isso o exemplo sai do bloco recuado.
const POWERSHELL_MESSAGES: &str =
    "    egeon send <endereço>           manda para ele o texto do stdin
    egeon trace                     registra o texto do stdin na trilha da bancada

No PowerShell, defina o UTF-8 sem BOM antes de passar texto ao `egeon`
(o padrão do PowerShell 5.1 troca acento por `?`) e mande o texto por
here-string, com o `'@` que fecha no começo da linha:

```powershell
$OutputEncoding = [Text.UTF8Encoding]::new($false)
@'
(o que você quer dizer)
'@ | egeon send <endereço>
@'
pedido: … — entrega: …
'@ | egeon trace
```
";

const POSIX_TASKS: &str =
    "    egeon task ask <id> <<'MB'      pergunta sobre ela — aparece na tarefa
    (a pergunta)
    MB
    egeon task note <id> <<'MB'     comenta nela: achado, decisão, o que fez
    (o comentário)
    MB
";

const POWERSHELL_TASKS: &str =
    "    egeon task ask <id>             pergunta sobre ela (texto no stdin) — aparece na tarefa
    egeon task note <id>            comenta nela (texto no stdin): achado, decisão, o que fez

```powershell
$OutputEncoding = [Text.UTF8Encoding]::new($false)
@'
(a pergunta)
'@ | egeon task ask <id>
```
";

/// A skill para o shell em que o agente roda os comandos: no PowerShell
/// (Windows, decisão 54) os exemplos são em PowerShell, no lugar do heredoc
/// do bash; o resto é o mesmo texto.
pub fn text(syntax: ShellSyntax) -> Cow<'static, str> {
    match syntax {
        ShellSyntax::Posix => Cow::Borrowed(body()),
        ShellSyntax::PowerShell => Cow::Owned(
            body()
                .replacen(POSIX_MESSAGES, POWERSHELL_MESSAGES, 1)
                .replacen(POSIX_TASKS, POWERSHELL_TASKS, 1),
        ),
    }
}

/// As skills que o app publica: a dos vizinhos e o manual do maestro (ADR-066).
/// Vão as duas para toda configuração — a do maestro diz logo no começo que só
/// vale para o terminal que o usuário marcou. `syntax` é a do shell do usuário.
pub fn published(maestro: &PublishedSkill, syntax: ShellSyntax) -> Vec<PublishedSkill> {
    vec![
        PublishedSkill {
            name: NAME.to_owned(),
            body: text(syntax).into_owned(),
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
