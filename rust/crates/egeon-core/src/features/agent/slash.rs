//! Um comando que o CLI do agente aceita começando com `/` — embutido, skill
//! do CLI, do usuário, do projeto ou de um plugin. É o que o composer do chat
//! oferece quando se digita `/`; quem sabe ler a lista de cada CLI é o
//! submódulo dele.

use unicode_normalization::{UnicodeNormalization, char::is_combining_mark};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SlashSource {
    Builtin,
    /// Skill que vem dentro do CLI (`/simplify`, `/loop`).
    Bundled,
    /// Da configuração do usuário (`commands/` ou `skills/` da pasta do CLI).
    User,
    /// Do `.claude/` do diretório do terminal.
    Project,
    Plugin(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SlashCommand {
    /// Sem a barra: `clear`, `figma:figma-use`.
    pub name: String,
    pub detail: String,
    pub source: SlashSource,
    /// Outros nomes que levam ao mesmo comando (`cost` → `usage`).
    pub aliases: Vec<String>,
}

impl SlashCommand {
    pub fn new(name: &str, detail: &str, source: SlashSource) -> Self {
        SlashCommand {
            name: name.to_owned(),
            detail: detail.to_owned(),
            source,
            aliases: Vec::new(),
        }
    }

    /// Quem casa com o que foi digitado depois da barra. Começo do nome primeiro
    /// — do nome inteiro, do que vem depois do `plugin:` ou de um apelido —,
    /// depois quem contém. Query vazia devolve tudo, na ordem recebida.
    pub fn matching(commands: &[SlashCommand], query: &str) -> Vec<SlashCommand> {
        if query.is_empty() {
            return commands.to_vec();
        }
        let needle = query.to_lowercase();
        let mut head = Vec::new();
        let mut tail = Vec::new();
        for command in commands {
            let name = command.name.to_lowercase();
            let short = name.rsplit(':').next().unwrap_or(&name);
            if name.starts_with(&needle)
                || short.starts_with(&needle)
                || command
                    .aliases
                    .iter()
                    .any(|a| a.to_lowercase().starts_with(&needle))
            {
                head.push(command.clone());
            } else if name.contains(&needle) {
                tail.push(command.clone());
            }
        }
        head.extend(tail);
        head
    }

    /// A busca da barra da lista: cada palavra tem de aparecer no nome, num
    /// apelido ou na descrição — sem caixa nem acento, em qualquer ordem. Quem
    /// casa tudo pelo nome vem antes de quem precisou da descrição.
    pub fn searching(commands: &[SlashCommand], text: &str) -> Vec<SlashCommand> {
        let folded = fold(text);
        let words: Vec<&str> = folded.split_whitespace().collect();
        if words.is_empty() {
            return commands.to_vec();
        }
        let mut by_name = Vec::new();
        let mut by_detail = Vec::new();
        for command in commands {
            let mut names = vec![command.name.as_str()];
            names.extend(command.aliases.iter().map(String::as_str));
            let name = fold(&names.join(" "));
            let all = format!("{name} {}", fold(&command.detail));
            if words.iter().all(|w| name.contains(w)) {
                by_name.push(command.clone());
            } else if words.iter().all(|w| all.contains(w)) {
                by_detail.push(command.clone());
            }
        }
        by_name.extend(by_detail);
        by_name
    }
}

fn fold(text: &str) -> String {
    text.nfd()
        .filter(|c| !is_combining_mark(*c))
        .collect::<String>()
        .to_lowercase()
}
