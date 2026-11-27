//! O manual do maestro (ADR-066): como desenhar uma bancada e o formato exato
//! do plano. Porte de `MaestroGuide.swift`, com o texto byte a byte.
//!
//! Um texto só, servido de dois jeitos: como skill do Claude Code
//! (`skills/egeon-maestro/SKILL.md`) e pelo `egeon guide`, que é como um CLI
//! sem skill chega nele.

use std::borrow::Cow;

use crate::features::terminal::shell::ShellSyntax;

pub const SKILL_NAME: &str = "egeon-maestro";

/// O manual, sem o frontmatter: o do macOS e do Linux.
pub const TEXT: &str = include_str!("guide.md");

const POSIX_COMMANDS: &str =
    "    egeon plan <<'JSON'  valida um plano e mostra o que mudaria (não muda nada)
    { ... }
    JSON
    egeon apply <<'JSON' valida e aplica — o mesmo plano
    { ... }
    JSON
    egeon guide          este texto
";

/// O `'@` que fecha o here-string só vale no começo da linha: por isso o
/// exemplo sai do bloco recuado e vai num bloco cercado.
const POWERSHELL_COMMANDS: &str = "    egeon plan           valida um plano (JSON no stdin) e mostra o que mudaria (não muda nada)
    egeon apply          valida e aplica — o mesmo plano
    egeon guide          este texto

No PowerShell, defina o UTF-8 sem BOM antes de passar texto ao `egeon`
(o padrão do PowerShell 5.1 troca acento por `?`) e mande o plano por
here-string, com o `'@` que fecha no começo da linha:

```powershell
$OutputEncoding = [Text.UTF8Encoding]::new($false)
@'
{ ... }
'@ | egeon plan
```
";

const POSIX_EXAMPLE: [&str; 2] = ["```bash\negeon plan <<'JSON'\n", "\nJSON\n```"];

const POWERSHELL_EXAMPLE: [&str; 2] = [
    "```powershell\n$OutputEncoding = [Text.UTF8Encoding]::new($false)\n@'\n",
    "\n'@ | egeon plan\n```",
];

/// O manual para o shell em que o maestro roda os comandos: no PowerShell
/// (Windows, decisão 54) os exemplos são em PowerShell, no lugar do heredoc
/// do bash; o resto é o mesmo texto.
pub fn text(syntax: ShellSyntax) -> Cow<'static, str> {
    match syntax {
        ShellSyntax::Posix => Cow::Borrowed(TEXT),
        ShellSyntax::PowerShell => Cow::Owned(
            TEXT.replacen(POSIX_COMMANDS, POWERSHELL_COMMANDS, 1)
                .replacen(POSIX_EXAMPLE[0], POWERSHELL_EXAMPLE[0], 1)
                .replacen(POSIX_EXAMPLE[1], POWERSHELL_EXAMPLE[1], 1),
        ),
    }
}

/// O frontmatter vai em bloco (`>-`): português com dois-pontos e travessão
/// num escalar solto derruba o YAML inteiro, calado.
pub fn skill(syntax: ShellSyntax) -> String {
    format!(
        r#"---
name: {SKILL_NAME}
description: >-
  Montar e reconfigurar a bancada do Egeon Deck sendo o terminal maestro
  — decidir quantos agentes, o papel, o modelo, o esforço e as regras de
  cada um, quem fala com quem, e aplicar tudo com `egeon apply`. Só vale
  quando `egeon status` mostra maestro true.
when_to_use: >-
  Quando o usuário pedir para montar, configurar, organizar ou
  reconfigurar a bancada ou um time de agentes — "monta a bancada para",
  "configura os terminais", "cria os agentes", "desenha o time",
  "organiza quem faz o quê", "troca o modelo do", "põe o revisor em
  opus", "aumenta o esforço do", "tira o terminal", "define as regras
  da bancada" — ou quando você for o maestro e o trabalho pedir mais de
  um agente.
---
"#
    ) + &text(syntax)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// O texto tem de sair igual ao do Swift: extraído do literal de
    /// `MaestroGuide.swift` como o compilador de lá o monta. Sem o legado na
    /// árvore, pula com aviso.
    #[test]
    fn text_is_the_same_as_the_legacy() {
        let legacy = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../../legado/app/Sources/EgeonDeck/Features/Maestro/Models/MaestroGuide.swift"
        );
        // Depois do corte o `legado/` sai da árvore: sem o arquivo não há com
        // o que comparar, e o teste pula falando. Com ele, divergir é falha.
        let Ok(source) = std::fs::read_to_string(legacy) else {
            crate::log!("guia do maestro: sem {legacy} — comparação com o Swift pulada");
            return;
        };
        let start = source.find("#\"\"\"\n").unwrap() + 5;
        let end = source.find("\n        \"\"\"#").unwrap();
        let text: Vec<&str> = source[start..end]
            .split('\n')
            .map(|l| l.strip_prefix("        ").unwrap_or(l))
            .collect();
        assert_eq!(TEXT, text.join("\n"));
    }

    #[test]
    fn skill_has_the_frontmatter_then_the_text() {
        for syntax in [ShellSyntax::Posix, ShellSyntax::PowerShell] {
            let skill = skill(syntax);
            assert!(skill.starts_with("---\nname: egeon-maestro\ndescription: >-\n"));
            assert!(skill.ends_with(&*text(syntax)));
            assert!(skill.contains("um agente.\n---\n# Maestro — montar a bancada"));
        }
    }

    /// Decisão 54: no PowerShell, nenhum heredoc sobra, o UTF-8 sem BOM vem
    /// antes de cada plano e todo here-string fecha no começo da linha.
    #[test]
    fn no_powershell_os_exemplos_sao_em_powershell() {
        assert_eq!(text(ShellSyntax::Posix), TEXT);
        let powershell = text(ShellSyntax::PowerShell);
        assert!(!powershell.contains("<<"), "{powershell}");
        assert!(!powershell.contains("```bash"), "{powershell}");
        let opened = powershell.lines().filter(|l| *l == "@'").count();
        let closed = powershell
            .lines()
            .filter(|l| *l == "'@ | egeon plan")
            .count();
        let encoding = powershell
            .lines()
            .filter(|l| *l == "$OutputEncoding = [Text.UTF8Encoding]::new($false)")
            .count();
        assert_eq!((opened, closed, encoding), (2, 2, 2), "{powershell}");
        assert!(powershell.contains("    egeon apply          valida e aplica"));
        assert!(powershell.ends_with("encerrar o turno\nem segundo plano."));
    }

    /// O `egeon guide` do CLI imprime uma cópia do texto: tem de ser esta,
    /// mais a quebra de linha do heredoc (como o `EgeonCLIBodyTests` do Swift).
    /// No Windows ele imprime a do PowerShell.
    #[test]
    fn cli_copy_is_the_same_text() {
        for (file, syntax) in [
            ("guide.md", ShellSyntax::Posix),
            ("guide-powershell.md", ShellSyntax::PowerShell),
        ] {
            let copy = format!("{}/../egeon-cli/src/{file}", env!("CARGO_MANIFEST_DIR"));
            let copied = std::fs::read_to_string(&copy)
                .unwrap_or_else(|e| panic!("a cópia do CLI sumiu de {copy}: {e}"));
            assert_eq!(copied, format!("{}\n", text(syntax)), "{file}");
        }
    }
}
