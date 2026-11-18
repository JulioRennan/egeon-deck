//! As regras que vão no fim do system prompt de um agente: as da bancada mais
//! as do terminal, na ordem (ADR-056).
//!
//! O texto é do usuário — o app não reescreve regra nenhuma. O que ele põe é a
//! moldura: de onde cada bloco veio, e a linha de precedência. Essa linha não é
//! zelo: medindo adesão, uma diretriz geral em conflito com uma restrição
//! específica costuma ser resolvida a favor da ação, e dizer qual vale fecha
//! essa porta.

pub const HEADER: &str = "Regras — valem sobre o papel acima. Quando um pedido \
conflitar com uma delas, siga a regra e diga por quê.";

/// O bloco pronto, ou `None` quando não há regra nenhuma dos dois lados.
pub fn agent_rules_block(workbench: Option<&str>, node: Option<&str>) -> Option<String> {
    let from_workbench = clean(workbench);
    let from_node = clean(node);
    if from_workbench.is_none() && from_node.is_none() {
        return None;
    }
    let mut out = vec![HEADER.to_owned()];
    // Com um bloco só, dizer de onde ele veio não informa nada que o agente
    // possa usar — ele não escolhe entre os dois, segue os dois.
    match (from_workbench, from_node) {
        (Some(w), Some(n)) => {
            out.push(format!("Da bancada:\n{w}"));
            out.push(format!("Deste terminal:\n{n}"));
        }
        (Some(only), None) | (None, Some(only)) => out.push(only),
        (None, None) => {}
    }
    Some(out.join("\n\n"))
}

fn clean(text: Option<&str>) -> Option<String> {
    let trimmed = text.unwrap_or("").trim();
    (!trimmed.is_empty()).then(|| trimmed.to_owned())
}
