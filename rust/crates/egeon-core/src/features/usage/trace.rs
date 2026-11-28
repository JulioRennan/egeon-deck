//! As conversas que a trilha carimbou: `## <data> · <nó>` e, na linha de baixo,
//! `CLI · modelo · conversa <8 primeiros>`. É o que permite achar os
//! transcripts de antes de cada `/clear` na primeira contagem.

use std::collections::HashSet;

/// `(nó, prefixo)` de cada conversa, sem repetir o par (prefixo sem caixa).
pub fn parse_conversations(text: &str) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();
    let mut node: Option<String> = None;
    for line in text.split('\n') {
        if line.starts_with("## ") {
            node = line.rsplit(" · ").next().map(|s| s.trim().to_owned());
            continue;
        }
        let Some(current) = &node else { continue };
        let Some(at) = line.find("conversa ") else {
            continue;
        };
        let rest = &line[at + "conversa ".len()..];
        let prefix: String = rest
            .chars()
            .take_while(|c| c.is_ascii_hexdigit() || *c == '-')
            .collect();
        if prefix.chars().count() >= 8 {
            out.push((current.clone(), prefix.chars().take(8).collect()));
        }
        node = None;
    }
    let mut seen = HashSet::new();
    out.retain(|(node, prefix)| seen.insert(format!("{node}#{}", prefix.to_lowercase())));
    out
}
