//! Uma linha da trilha da bancada: um agente dizendo o que fez num turno.
//!
//! O texto é do agente (`egeon trace`); o resto é carimbo do app — quem falou
//! vem do pid do socket, nunca do texto (ADR-012), e CLI, modelo e conversa
//! vêm do nó. Assim a trilha diz "o agente X, rodando o Claude Code com o
//! modelo Y na conversa Z, fez tal coisa" sem que o agente possa se passar por
//! outro nem inventar de onde veio.

use std::time::SystemTime;

use unicode_segmentation::UnicodeSegmentation;

use crate::features::chat::time::format_clock;

/// Teto de segurança, não de estilo: o agente é instruído a escrever uma ou
/// duas linhas, mas um que despeje a resposta inteira não pode transformar a
/// trilha num transcript.
pub const TEXT_LIMIT: usize = 1500;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TraceEntry {
    pub address: String,
    /// A bancada de verdade, não o nome: o nome se repete quando você apaga e
    /// recria; o id não.
    pub workbench_id: String,
    pub at: SystemTime,
    pub cli: Option<String>,
    pub model: Option<String>,
    pub conversation: Option<String>,
    pub text: String,
}

impl TraceEntry {
    pub fn new(
        address: impl Into<String>,
        workbench_id: impl Into<String>,
        at: SystemTime,
        text: &str,
    ) -> Self {
        TraceEntry {
            address: address.into(),
            workbench_id: workbench_id.into(),
            at,
            cli: None,
            model: None,
            conversation: None,
            text: cap(text, TEXT_LIMIT),
        }
    }

    pub fn stamped(
        mut self,
        cli: Option<String>,
        model: Option<String>,
        conversation: Option<String>,
    ) -> Self {
        self.cli = cli;
        self.model = model;
        self.conversation = conversation;
        self
    }

    /// O bloco que entra no arquivo. `utc_offset_secs` é o fuso do carimbo
    /// (segundos a leste de UTC): o Swift usa o do sistema, e o core não o lê
    /// por conta própria.
    pub fn markdown(&self, utc_offset_secs: i64) -> String {
        let mut stamp: Vec<String> = [&self.cli, &self.model]
            .into_iter()
            .flatten()
            .cloned()
            .collect();
        if let Some(conversation) = &self.conversation {
            let short: String = conversation.chars().take(8).collect();
            stamp.push(format!("conversa {short}"));
        }
        // Só o id do nó: a bancada é o arquivo.
        let mut lines = vec![format!(
            "## {} · {}",
            minute(self.at, utc_offset_secs),
            self.node()
        )];
        if !stamp.is_empty() {
            lines.push(stamp.join(" · "));
        }
        lines.push(String::new());
        lines.push(if self.text.is_empty() {
            "—".to_owned()
        } else {
            self.text.clone()
        });
        lines.join("\n") + "\n\n"
    }

    /// O nome da bancada, a parte antes da primeira `/` do endereço.
    pub fn workbench(&self) -> &str {
        parts(&self.address)
            .first()
            .copied()
            .unwrap_or(&self.address)
    }

    /// O id do nó, a parte depois da primeira `/`.
    pub fn node(&self) -> &str {
        parts(&self.address)
            .last()
            .copied()
            .unwrap_or(&self.address)
    }
}

/// `split(separator: "/", maxSplits: 1)` do Swift, que descarta pedaço vazio.
fn parts(address: &str) -> Vec<&str> {
    match address.split_once('/') {
        Some((a, b)) => vec![a, b],
        None => vec![address],
    }
    .into_iter()
    .filter(|p| !p.is_empty())
    .collect()
}

/// Aparado nas pontas e cortado em `limit` caracteres, com `…` quando cortou.
pub fn cap(text: &str, limit: usize) -> String {
    let trimmed = text.trim();
    // Por grafema, como o `count` e o `prefix` do Swift: o corte não parte um
    // acento decomposto, uma bandeira ou um emoji composto.
    if trimmed.graphemes(true).count() <= limit {
        return trimmed.to_owned();
    }
    let mut out: String = trimmed.graphemes(true).take(limit).collect();
    out.push('…');
    out
}

/// `yyyy-MM-dd HH:mm`, o carimbo do cabeçalho de cada entrada.
fn minute(at: SystemTime, utc_offset_secs: i64) -> String {
    // `yyyyMMdd-HHmmss` → `yyyy-MM-dd HH:mm`.
    let c = format_clock(at, utc_offset_secs);
    format!(
        "{}-{}-{} {}:{}",
        &c[0..4],
        &c[4..6],
        &c[6..8],
        &c[9..11],
        &c[11..13]
    )
}

/// O cabeçalho do arquivo: o nome da bancada no momento em que a trilha
/// nasceu, e o id que a identifica de verdade — é ele que nomeia a pasta.
pub fn header(workbench: &str, id: &str) -> String {
    format!(
        "# {workbench}\n\
         bancada `{id}`\n\
         \n\
         Trilha da bancada: cada agente registra, ao fim do turno, o que foi pedido\n\
         e o que entregou (`egeon trace`); o terminal comum registra cada comando.\n\
         Quem escreveu, CLI, modelo e conversa são carimbados pelo Egeon Deck.\n\
         \n"
    )
}
