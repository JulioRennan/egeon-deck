//! O texto de cada linha da bolha — a parte de `ChatBlockLayout` que é regra e
//! não medida. Altura, largura e cor são da UI (o TextKit do Swift não tem
//! equivalente aqui); o que a linha DIZ é igual ao do legado e é provado nos
//! testes.

use std::time::SystemTime;

use super::blocks::{ChatCost, ChatGroupLevel, ChatLive};
use super::model::ChatStep;
use super::time::signed_secs;

/// "14:02" no fuso dado (`offset_secs` a leste de UTC): o relógio é parâmetro
/// porque o core não lê fuso por conta própria.
pub fn clock(at: SystemTime, offset_secs: i64) -> String {
    let rest = (signed_secs(at) + offset_secs).rem_euclid(86_400);
    format!("{:02}:{:02}", rest / 3600, rest % 3600 / 60)
}

/// "US$ 0,42 · 14:32": o custo do turno antes da hora (ADR-085). `None` é
/// "agora".
pub fn header_time(at: Option<SystemTime>, cost: Option<&ChatCost>, offset_secs: i64) -> String {
    let time = at.map_or_else(|| "agora".to_owned(), |at| clock(at, offset_secs));
    match cost {
        Some(cost) => format!("{} · {time}", cost.text),
        None => time,
    }
}

/// Como no WhatsApp: quem mandou em cima (quando não foi o usuário), e — só
/// quando a mensagem não é contínua — a menção `@destinatário` no começo do texto.
/// Um marcando o outro; sem seta.
pub fn prompt(text: &str, to_id: &str, from: Option<&str>, mention: bool) -> String {
    let mut out = String::new();
    if let Some(from) = from {
        out.push_str(&format!("✦ {from}\n"));
    }
    if mention {
        out.push_str(&format!("@{to_id} "));
    }
    out.push_str(text);
    out
}

/// Um passo como o terminal o mostra: a linha, o comando por extenso, a saída
/// recuada com `⎿`. Recolhido, só a linha — com `+a −b` e o tamanho da saída para
/// não perder a conta — e o chevron avisa que há o que abrir.
pub fn step(step: &ChatStep, expanded: bool) -> String {
    let mut out = String::new();
    if step.is_expandable() {
        out.push_str(if expanded { "▾ " } else { "▸ " });
    }
    out.push_str(&format!("{}  {}", step.glyph, step.text));
    if !expanded {
        if let Some((added, removed)) = step.diff_counts() {
            out.push_str(&format!("  +{added} −{removed}"));
        }
        if let Some(output) = &step.output {
            let n = output.split('\n').filter(|l| !l.is_empty()).count();
            out.push_str(&format!("  ⎿ {n} linha{}", if n == 1 { "" } else { "s" }));
        }
        return out;
    }
    if let Some(detail) = &step.detail {
        for line in detail.split('\n') {
            out.push_str(&format!("\n   {line}"));
        }
    }
    if let Some(output) = &step.output {
        for (i, line) in output.split('\n').enumerate() {
            out.push_str(&format!("\n   {}{line}", if i == 0 { "⎿ " } else { "  " }));
        }
    }
    out
}

/// A capa de uma sequência de passos. Fechada diz quantos são e onde a sequência
/// parou; aberta é só o contador — os títulos vêm abaixo.
pub fn group(count: usize, last: &str, level: ChatGroupLevel) -> String {
    let mut out = format!(
        "{}⚙  {count} passos",
        if level == ChatGroupLevel::Summary {
            "▸ "
        } else {
            "▾ "
        }
    );
    match level {
        ChatGroupLevel::Summary => out.push_str(&format!("  ·  {last}")),
        ChatGroupLevel::Details => out.push_str("  ·  detalhes"),
        ChatGroupLevel::Titles => {}
    }
    out
}

/// O texto da linha de status: spinner (ou ● laranja) e o que está fazendo.
pub fn status(live: &ChatLive, spinner: char) -> String {
    if matches!(live, ChatLive::Asking) {
        return format!("● {}", live.label());
    }
    format!("{spinner} {}", live.label())
}
