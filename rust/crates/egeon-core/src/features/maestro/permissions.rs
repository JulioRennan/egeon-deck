//! Pedido de permissão do time chegando ao maestro que aprova (ADR-080).
//! Porte de `MaestroPermissions.swift`.

use serde_json::{Value, json};

use crate::features::node::model::NodeConfig;
use crate::features::permission::model::PermissionAsk;
use crate::features::workbench::model::WorkbenchConfig;

/// Só permissão de ferramenta: a pergunta do `AskUserQuestion` é a VOCÊ que o
/// agente faz.
pub fn delegable(ask: &PermissionAsk) -> bool {
    ask.tool != "AskUserQuestion"
}

/// O maestro da bancada que aprova pelo time, quando há um e o pedido não é
/// dele — aprovar o próprio pedido seria não ter pedido.
pub fn approver<'a>(ask: &PermissionAsk, bench: &'a WorkbenchConfig) -> Option<&'a NodeConfig> {
    if !delegable(ask) || !ask.address.starts_with(&format!("{}/", bench.name)) {
        return None;
    }
    bench.nodes.iter().find(|n| {
        n.approves_team_permissions() && format!("{}/{}", bench.name, n.id) != ask.address
    })
}

/// UMA linha, curta: texto longo ou de várias linhas entra no Claude Code
/// como "colado", e o modelo não age sobre colado sem você confirmar. Tem o id
/// e os comandos prontos porque o pedido expira junto com o gancho.
pub fn notice(ask: &PermissionAsk) -> String {
    let who = ask
        .address
        .rsplit('/')
        .find(|s| !s.is_empty())
        .unwrap_or(&ask.address);
    let what = one_line(&ask.summary, 140);
    let why = ask
        .detail
        .as_deref()
        .map(|d| one_line(d, 80))
        .filter(|d| !d.is_empty())
        .map(|d| format!(" ({d})"))
        .unwrap_or_default();
    let always = if ask.can_always_allow() {
        " (ou --always)"
    } else {
        ""
    };
    format!(
        "[ED] pedido de permissão de {who} — {}: {what}{why} — responda: egeon allow {}{always} · \
         egeon deny {}",
        ask.tool, ask.id, ask.id
    )
}

fn one_line(text: &str, max: usize) -> String {
    let flat = text
        .split([
            '\n', '\r', '\u{2028}', '\u{2029}', '\u{0B}', '\u{0C}', '\u{85}',
        ])
        .collect::<Vec<_>>()
        .join(" ");
    let flat = flat.trim();
    if flat.chars().count() > max {
        let mut out: String = flat.chars().take(max - 1).collect();
        out.push('…');
        out
    } else {
        flat.to_owned()
    }
}

/// Como o pedido aparece em `egeon permissions`.
pub fn listing(ask: &PermissionAsk) -> Value {
    let mut out = json!({"id": ask.id, "from": ask.address, "tool": ask.tool,
        "summary": ask.summary, "always": ask.can_always_allow()});
    if let (Some(detail), Some(map)) = (&ask.detail, out.as_object_mut()) {
        map.insert("detail".into(), json!(detail));
    }
    out
}
