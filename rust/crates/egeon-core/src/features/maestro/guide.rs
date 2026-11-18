//! O manual do maestro (ADR-066): como desenhar uma bancada e o formato exato
//! do plano. Porte de `MaestroGuide.swift`, com o texto byte a byte.
//!
//! Um texto só, servido de dois jeitos: como skill do Claude Code
//! (`skills/egeon-maestro/SKILL.md`) e pelo `egeon guide`, que é como um CLI
//! sem skill chega nele.

pub const SKILL_NAME: &str = "egeon-maestro";

/// O manual, sem o frontmatter.
pub const TEXT: &str = include_str!("guide.md");

/// O frontmatter vai em bloco (`>-`): português com dois-pontos e travessão
/// num escalar solto derruba o YAML inteiro, calado.
pub fn skill() -> String {
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
    ) + TEXT
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
        let skill = skill();
        assert!(skill.starts_with("---\nname: egeon-maestro\ndescription: >-\n"));
        assert!(skill.ends_with(TEXT));
        assert!(skill.contains("um agente.\n---\n# Maestro — montar a bancada"));
    }

    /// O `egeon guide` do CLI imprime uma cópia do texto: tem de ser esta,
    /// mais a quebra de linha do heredoc (como o `EgeonCLIBodyTests` do Swift).
    #[test]
    fn cli_copy_is_the_same_text() {
        let copy = concat!(env!("CARGO_MANIFEST_DIR"), "/../egeon-cli/src/guide.md");
        let text = std::fs::read_to_string(copy)
            .unwrap_or_else(|e| panic!("a cópia do CLI sumiu de {copy}: {e}"));
        assert_eq!(text, format!("{TEXT}\n"));
    }
}
