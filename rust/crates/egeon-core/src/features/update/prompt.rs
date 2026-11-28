//! O texto do aviso de versão nova. A folha em si (botões, caixa de
//! atualizar sozinho) é da UI.

const NOTES_LIMIT: usize = 420;

/// As novidades (cortadas), o custo de reiniciar e o que o clique autoriza.
pub fn text(notes: &str, agents: usize) -> String {
    let mut parts: Vec<String> = Vec::new();
    let trimmed = notes.trim();
    if !trimmed.is_empty() {
        parts.push(if trimmed.chars().count() > NOTES_LIMIT {
            let mut cut: String = trimmed.chars().take(NOTES_LIMIT).collect();
            cut.push('…');
            cut
        } else {
            trimmed.to_owned()
        });
    }
    if agents > 0 {
        let plural = if agents == 1 {
            "1 agente aberto".to_owned()
        } else {
            format!("{agents} agentes abertos")
        };
        parts.push(format!(
            "Reiniciar encerra o que estiver rodando: {plural}. As conversas são retomadas quando o app voltar."
        ));
    }
    // O app ainda não tem assinatura da Apple: dizer o que o clique autoriza.
    parts.push(
        "O app não tem assinatura da Apple. Ao atualizar, ele confere a assinatura própria da \
         versão baixada e tira dela a quarentena do macOS."
            .to_owned(),
    );
    parts.join("\n\n")
}
