//! O que o Claude Code oferece no `/` de um terminal.
//!
//! Sem perguntar ao CLI: a lista só existe dentro da TUI, e a saída
//! `stream-json` que a traz custa uma chamada à API. Junta-se o que ele junta,
//! de onde ele lê — a pasta de configuração DO NÓ (cada um escolhe a sua,
//! ADR-054), o `.claude/` do diretório e dos pais até a raiz do repositório, os
//! plugins habilitados e o que vem sincronizado do claude.ai —, mais a
//! `skill_listing` do transcript (as skills que a sessão carregou de fato,
//! inclusive as do binário) e os embutidos lidos do binário. Relido a cada
//! abertura da lista, para skill instalada agora aparecer sem reiniciar nada.

use std::collections::{BTreeMap, BTreeSet, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde_json::{Map, Value};

use super::command_registry::CommandRegistry;
use super::find;
use crate::features::agent::model::{AgentProfile, expand_tilde};
use crate::features::agent::slash::{SlashCommand, SlashSource};

/// A lista do nó, pela configuração que ele sobe: a escolhida no nó, senão a do
/// perfil, senão o `~/.claude`. `None` quando o perfil não é Claude Code.
pub fn commands_for_profile(
    profile: &AgentProfile,
    node_config: Option<&str>,
    cwd: &Path,
    transcript: Option<&Path>,
    binary: Option<&CommandRegistry>,
    home: &Path,
) -> Option<Vec<SlashCommand>> {
    if profile.command.first().map(String::as_str) != Some("claude") {
        return None;
    }
    let chosen = node_config.map(str::to_owned).or_else(|| {
        profile
            .config_env
            .as_ref()
            .and_then(|v| profile.resolved_environment(home).get(v).cloned())
    });
    let path = match chosen {
        Some(chosen) => expand_tilde(&chosen, home),
        None => profile.default_config_path(home)?,
    };
    let loaded = transcript.map(skill_listing_at);
    Some(commands(&path, Some(cwd), loaded.as_deref(), binary))
}

/// `loaded` é a `skill_listing` da sessão (`None` sem transcript); `binary`, o
/// que se leu do executável (`None` antes da primeira leitura).
pub fn commands(
    config_dir: &Path,
    cwd: Option<&Path>,
    loaded: Option<&[(String, String)]>,
    binary: Option<&CommandRegistry>,
) -> Vec<SlashCommand> {
    let mut out: Vec<SlashCommand> = Vec::new();
    // A `skill_listing` traz também quem o disco tira do `/`.
    let mut hidden: BTreeSet<String> = binary
        .map(|b| b.hidden.iter().cloned().collect())
        .unwrap_or_default();
    for root in cwd.map(project_roots).unwrap_or_default() {
        out.extend(scan(&root, &SlashSource::Project, None, &mut hidden));
    }
    out.extend(scan(config_dir, &SlashSource::User, None, &mut hidden));
    let plugins = enabled_plugins(config_dir, cwd)
        .into_iter()
        .chain(synced_plugins(config_dir));
    for (plugin, root) in plugins {
        out.extend(scan(
            &root,
            &SlashSource::Plugin(plugin.clone()),
            Some(&plugin),
            &mut hidden,
        ));
    }
    out.extend(synced_skills(config_dir, &mut hidden));

    for (name, detail) in loaded.unwrap_or_default() {
        if hidden.contains(name) {
            continue;
        }
        // Como o `split(maxSplits: 1)` do Swift, que descarta o pedaço vazio:
        // `:x` e `a:` não têm prefixo de plugin.
        let prefix = name
            .split_once(':')
            .filter(|(before, after)| !before.is_empty() && !after.is_empty())
            .map(|(p, _)| p.to_owned());
        out.push(SlashCommand::new(
            name,
            detail,
            prefix.map_or(SlashSource::Bundled, SlashSource::Plugin),
        ));
    }
    // Com a lista da sessão, só as do binário que ela nunca traz: as que rodam
    // só digitadas. Sem ela, todas — melhor sobrar que faltar.
    for skill in binary.map(|b| b.skills.as_slice()).unwrap_or_default() {
        if loaded.is_none() || skill.user_only {
            let mut command = SlashCommand::new(&skill.name, &skill.detail, SlashSource::Bundled);
            command.aliases = skill.aliases.clone().unwrap_or_default();
            out.push(command);
        }
    }

    let read = binary.map(|b| b.builtins.as_slice()).unwrap_or_default();
    let ours = builtins();
    if read.is_empty() {
        out.extend(ours);
    } else {
        let captions: BTreeMap<&str, &str> = ours
            .iter()
            .map(|c| (c.name.as_str(), c.detail.as_str()))
            .collect();
        for entry in read {
            let detail = captions
                .get(entry.name.as_str())
                .copied()
                .unwrap_or(&entry.detail);
            let mut command = SlashCommand::new(&entry.name, detail, SlashSource::Builtin);
            command.aliases = entry.aliases.clone().unwrap_or_default();
            out.push(command);
        }
    }
    // O primeiro vence: projeto sobre o seu, o seu sobre o embutido — a mesma
    // precedência do CLI.
    let mut seen = HashSet::new();
    out.retain(|c| seen.insert(c.name.clone()));
    out
}

/// O `.claude/` do diretório e de cada pai até a raiz do repositório — o mais
/// perto primeiro. Fora de repositório, só o do diretório.
pub fn project_roots(cwd: &Path) -> Vec<PathBuf> {
    let mut roots = Vec::new();
    let mut dir = lexical(cwd);
    loop {
        roots.push(dir.join(".claude"));
        // `.git` arquivo é worktree: a busca para nela, como no CLI.
        if dir.join(".git").exists() {
            return roots;
        }
        if dir.components().count() <= 1 {
            return roots.into_iter().take(1).collect();
        }
        match dir.parent() {
            Some(parent) => dir = parent.to_path_buf(),
            None => return roots.into_iter().take(1).collect(),
        }
    }
}

/// O caminho com `.` e `..` resolvidos, sem tocar o disco.
fn lexical(path: &Path) -> PathBuf {
    use std::path::Component;
    let mut out = PathBuf::new();
    for part in path.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other),
        }
    }
    out
}

fn named(prefix: Option<&str>, name: &str) -> String {
    prefix.map_or_else(|| name.to_owned(), |p| format!("{p}:{name}"))
}

/// Os `.md` de uma pasta, recursivo.
fn markdown_files(folder: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(folder) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            markdown_files(&path, out);
        } else if path.extension().and_then(|e| e.to_str()) == Some("md") {
            out.push(path);
        }
    }
}

/// `commands/*.md` (subpasta vira `pasta:nome`), `skills/<nome>/SKILL.md` e o
/// `SKILL.md` na raiz, que é o de plugin de uma skill só.
pub fn scan(
    root: &Path,
    source: &SlashSource,
    prefix: Option<&str>,
    hidden: &mut BTreeSet<String>,
) -> Vec<SlashCommand> {
    let mut found = Vec::new();
    let commands = lexical(&root.join("commands"));
    let mut files = Vec::new();
    markdown_files(&commands, &mut files);
    for file in files {
        let Ok(text) = fs::read_to_string(&file) else {
            continue;
        };
        let meta = Frontmatter::parse(&text);
        let relative = file
            .with_extension("")
            .strip_prefix(&commands)
            .map(|r| {
                r.components()
                    .map(|c| c.as_os_str().to_string_lossy().into_owned())
                    .collect::<Vec<_>>()
                    .join(":")
            })
            .unwrap_or_default();
        let name = named(prefix, &relative);
        if !meta.invocable {
            hidden.insert(name);
            continue;
        }
        let detail = meta.description.or(meta.first_line).unwrap_or_default();
        found.push(SlashCommand::new(&name, &detail, source.clone()));
    }

    found.extend(skills(&root.join("skills"), source, prefix, hidden));
    if prefix.is_some()
        && let Ok(text) = fs::read_to_string(root.join("SKILL.md"))
    {
        let meta = Frontmatter::parse(&text);
        let base = meta.name.clone().unwrap_or_else(|| {
            root.file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default()
        });
        let name = named(prefix, &base);
        if meta.invocable {
            found.push(SlashCommand::new(
                &name,
                &meta.description.unwrap_or_default(),
                source.clone(),
            ));
        } else {
            hidden.insert(name);
        }
    }
    found.sort_by(|a, b| a.name.cmp(&b.name));
    found
}

/// Cada `<pasta>/SKILL.md` de um diretório.
pub fn skills(
    folder: &Path,
    source: &SlashSource,
    prefix: Option<&str>,
    hidden: &mut BTreeSet<String>,
) -> Vec<SlashCommand> {
    let mut found = Vec::new();
    let Ok(folders) = fs::read_dir(folder) else {
        return found;
    };
    for entry in folders.flatten() {
        let path = entry.path();
        let Ok(text) = fs::read_to_string(path.join("SKILL.md")) else {
            continue;
        };
        let meta = Frontmatter::parse(&text);
        let base = meta.name.clone().unwrap_or_else(|| {
            path.file_name()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default()
        });
        let name = named(prefix, &base);
        if !meta.invocable {
            hidden.insert(name);
            continue;
        }
        found.push(SlashCommand::new(
            &name,
            &meta.description.unwrap_or_default(),
            source.clone(),
        ));
    }
    found
}

fn json(path: &Path) -> Option<Value> {
    serde_json::from_slice(&fs::read(path).ok()?).ok()
}

fn object_at(value: Option<&Value>, key: &str) -> Map<String, Value> {
    value
        .and_then(|v| v.get(key))
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default()
}

/// Os plugins ligados — no `settings.json` da configuração e nos do projeto, que
/// vencem —, com a pasta instalada de cada um. O nome no `/` é o do plugin sem o
/// `@marketplace`.
pub fn enabled_plugins(config_dir: &Path, cwd: Option<&Path>) -> Vec<(String, PathBuf)> {
    let mut enabled = object_at(
        json(&config_dir.join("settings.json")).as_ref(),
        "enabledPlugins",
    );
    if let Some(cwd) = cwd {
        for file in ["settings.json", "settings.local.json"] {
            let project = json(&cwd.join(".claude").join(file));
            for (key, value) in object_at(project.as_ref(), "enabledPlugins") {
                enabled.insert(key, value);
            }
        }
    }
    let installed = object_at(
        json(&config_dir.join("plugins/installed_plugins.json")).as_ref(),
        "plugins",
    );
    let projects = cwd.map(project_roots).unwrap_or_default();
    let mut keys: Vec<&String> = enabled.keys().collect();
    keys.sort();
    keys.into_iter()
        .filter_map(|key| {
            if enabled.get(key)?.as_bool() != Some(true) {
                return None;
            }
            let entries = installed.get(key)?.as_array()?;
            let path = install_path(entries, &projects)?;
            let name = key.split('@').next().unwrap_or(key).to_owned();
            Some((name, PathBuf::from(path)))
        })
        .collect()
}

/// A instalação que vale aqui: a deste projeto (o diretório ou um pai até a raiz
/// do repositório), senão a do usuário, senão a primeira. Instalação de projeto
/// num pai mais acima — a home, por exemplo — não é deste.
pub fn install_path(entries: &[Value], projects: &[PathBuf]) -> Option<String> {
    let here: HashSet<PathBuf> = projects
        .iter()
        .filter_map(|p| p.parent().map(lexical))
        .collect();
    let scope = |e: &Value| e.get("scope").and_then(Value::as_str).map(str::to_owned);
    let project = entries.iter().find(|e| {
        scope(e).as_deref() == Some("project")
            && e.get("projectPath")
                .and_then(Value::as_str)
                .is_some_and(|root| here.contains(&lexical(Path::new(root))))
    });
    let chosen = project
        .or_else(|| entries.iter().find(|e| scope(e).as_deref() == Some("user")))
        .or_else(|| entries.first());
    chosen?.get("installPath")?.as_str().map(str::to_owned)
}

/// As pastas de sincronização do claude.ai: `<raiz>/<conta>/manifest.json`.
fn synced_buckets(root: &Path) -> Vec<(PathBuf, Value)> {
    let mut buckets: Vec<PathBuf> = fs::read_dir(root)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .collect();
    buckets.sort();
    buckets
        .into_iter()
        .filter_map(|bucket| json(&bucket.join("manifest.json")).map(|m| (bucket, m)))
        .collect()
}

/// As skills da conta do claude.ai, que o CLI chama de `anthropic-skills:`.
pub fn synced_skills(config_dir: &Path, hidden: &mut BTreeSet<String>) -> Vec<SlashCommand> {
    let mut found = Vec::new();
    for (bucket, manifest) in synced_buckets(&config_dir.join("skills/synced")) {
        let listed: HashSet<String> = manifest
            .get("skills")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(|s| s.get("name").and_then(Value::as_str).map(str::to_owned))
            .collect();
        let source = SlashSource::Plugin("anthropic-skills".to_owned());
        found.extend(
            skills(&bucket, &source, Some("anthropic-skills"), hidden)
                .into_iter()
                .filter(|c| listed.contains(&c.name["anthropic-skills:".len()..])),
        );
    }
    found.sort_by(|a, b| a.name.cmp(&b.name));
    found
}

/// Os plugins da conta do claude.ai. Cada geração nova desce numa pasta
/// `<nome>~g<n>` ao lado da anterior; vale a do manifesto.
pub fn synced_plugins(config_dir: &Path) -> Vec<(String, PathBuf)> {
    let mut out = Vec::new();
    for (bucket, manifest) in synced_buckets(&config_dir.join("plugins/synced")) {
        for plugin in manifest
            .get("plugins")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let Some(name) = plugin.get("name").and_then(Value::as_str) else {
                continue;
            };
            let generation = plugin
                .get("generation")
                .and_then(Value::as_i64)
                .map(|g| bucket.join(format!("{name}~g{g}")))
                .filter(|p| p.exists());
            let folder = generation.unwrap_or_else(|| bucket.join(name));
            if folder.exists() {
                out.push((name.to_owned(), folder));
            }
        }
    }
    out
}

const LISTING_MARK: &[u8] = b"\"skill_listing\"";

/// As skills que a sessão carregou, da `skill_listing` do transcript — a
/// primeira (`isInitial`) e as que chegam depois somando. É a lista do modelo,
/// não do menu: quem tem `user-invocable: false` também vem.
pub fn skill_listing_at(path: &Path) -> Vec<(String, String)> {
    fs::read(path)
        .map(|d| skill_listing(&d))
        .unwrap_or_default()
}

pub fn skill_listing(data: &[u8]) -> Vec<(String, String)> {
    let mut order: Vec<String> = Vec::new();
    let mut details: BTreeMap<String, String> = BTreeMap::new();
    let mut cursor = 0;
    while let Some(hit) = find(data, LISTING_MARK, cursor) {
        let start = data[..hit]
            .iter()
            .rposition(|b| *b == b'\n')
            .map_or(0, |i| i + 1);
        let end = data[hit + LISTING_MARK.len()..]
            .iter()
            .position(|b| *b == b'\n')
            .map_or(data.len(), |i| hit + LISTING_MARK.len() + i);
        cursor = end;
        let Ok(line) = serde_json::from_slice::<Value>(&data[start..end]) else {
            continue;
        };
        let Some(attachment) = line.get("attachment") else {
            continue;
        };
        if attachment.get("type").and_then(Value::as_str) != Some("skill_listing") {
            continue;
        }
        if attachment.get("isInitial").and_then(Value::as_bool) == Some(true) {
            order.clear();
            details.clear();
        }
        let mut described: BTreeMap<String, String> = BTreeMap::new();
        let content = attachment
            .get("content")
            .and_then(Value::as_str)
            .unwrap_or("");
        for row in content.split('\n').filter(|r| r.starts_with("- ")) {
            if let Some(colon) = row.find(": ") {
                described.insert(row[2..colon].to_owned(), row[colon + 2..].to_owned());
            }
        }
        let names: Vec<String> = match attachment.get("names").and_then(Value::as_array) {
            Some(list) => list
                .iter()
                .filter_map(|n| n.as_str().map(str::to_owned))
                .collect(),
            None => described.keys().cloned().collect(),
        };
        for name in names {
            if details.contains_key(&name) {
                continue;
            }
            order.push(name.clone());
            details.insert(
                name.clone(),
                described.get(&name).cloned().unwrap_or_default(),
            );
        }
    }
    order
        .into_iter()
        .map(|n| {
            let d = details.get(&n).cloned().unwrap_or_default();
            (n, d)
        })
        .collect()
}

/// Os embutidos de uso comum, com legenda em português. Valem sozinhos enquanto
/// o binário não foi lido; depois, só emprestam a legenda.
pub fn builtins() -> Vec<SlashCommand> {
    [
        ("clear", "Limpa a conversa e começa do zero"),
        ("compact", "Resume a conversa para liberar contexto"),
        ("context", "Mostra quanto do contexto está ocupado"),
        ("model", "Troca o modelo"),
        ("config", "Abre as configurações"),
        ("cost", "Custo e duração da sessão"),
        ("usage", "Uso do plano e limites"),
        ("status", "Versão, modelo, conta e conexões"),
        ("resume", "Retoma uma conversa anterior"),
        ("rewind", "Volta a conversa ou o código a um ponto anterior"),
        ("memory", "Edita os arquivos de memória (CLAUDE.md)"),
        ("init", "Cria o CLAUDE.md do projeto"),
        ("review", "Revisa um pull request"),
        (
            "security-review",
            "Revisão de segurança das mudanças pendentes",
        ),
        ("permissions", "Regras de permissão de ferramentas"),
        ("agents", "Gerencia subagentes"),
        ("mcp", "Servidores MCP"),
        ("hooks", "Ganchos configurados"),
        ("plugin", "Gerencia plugins"),
        ("add-dir", "Adiciona outra pasta de trabalho"),
        ("export", "Exporta a conversa"),
        ("doctor", "Diagnóstico da instalação"),
        ("help", "Ajuda e lista de comandos"),
    ]
    .iter()
    .map(|(name, detail)| SlashCommand::new(name, detail, SlashSource::Builtin))
    .collect()
}

/// O cabeçalho `---` de um comando ou skill — só as chaves que a lista usa.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Frontmatter {
    pub name: Option<String>,
    pub description: Option<String>,
    /// `user-invocable: false` tira a skill do `/` (ela só roda pelo modelo).
    pub invocable: bool,
    /// Para comando sem `description`: a primeira linha de texto do corpo.
    pub first_line: Option<String>,
}

impl Frontmatter {
    pub fn parse(text: &str) -> Frontmatter {
        let mut meta = Frontmatter {
            name: None,
            description: None,
            invocable: true,
            first_line: None,
        };
        let all: Vec<&str> = text.lines().collect();
        let mut index = 0;
        if all.first().is_some_and(|l| l.trim() == "---") {
            index = 1;
            let mut folding: Option<String> = None;
            let mut folded: Vec<String> = Vec::new();
            while index < all.len() {
                let line = all[index];
                index += 1;
                if line.trim() == "---" {
                    break;
                }
                // `description: >-` e afins: o valor vem nas linhas recuadas.
                if folding.is_some() && (line.starts_with(' ') || line.starts_with('\t')) {
                    folded.push(line.trim().to_owned());
                    continue;
                }
                if let Some(key) = folding.take() {
                    meta.set(&key, &folded.join(" "));
                    folded.clear();
                }
                let Some(colon) = line.find(':') else {
                    continue;
                };
                let key = line[..colon].trim();
                let value = line[colon + 1..].trim();
                if [">", ">-", "|", "|-", ""].contains(&value) {
                    folding = Some(key.to_owned());
                    continue;
                }
                meta.set(key, value);
            }
            if let Some(key) = folding {
                meta.set(&key, &folded.join(" "));
            }
        }
        meta.first_line = all[index..]
            .iter()
            .map(|l| l.trim_matches(|c: char| c == '#' || c.is_whitespace()))
            .find(|l| !l.is_empty())
            .map(str::to_owned);
        meta
    }

    fn set(&mut self, key: &str, raw: &str) {
        let quoted = raw.chars().count() >= 2
            && ((raw.starts_with('"') && raw.ends_with('"'))
                || (raw.starts_with('\'') && raw.ends_with('\'')));
        let value = if quoted { &raw[1..raw.len() - 1] } else { raw };
        match key {
            "name" => self.name = (!value.is_empty()).then(|| value.to_owned()),
            "description" => self.description = (!value.is_empty()).then(|| value.to_owned()),
            "user-invocable" => self.invocable = value.to_lowercase() != "false",
            _ => {}
        }
    }
}
