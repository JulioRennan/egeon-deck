//! O pedido de entrega que o socket aceita e o prompt que sai dele. Porte de
//! `DispatchRequest.swift` e `SenderBacklog.swift`.

use serde::{Deserialize, Serialize};

/// A marca de tudo o que o APP põe num prompt — a mesma dos marcadores de fim
/// de turno, para quem lê o terminal reconhecer de onde veio (ADR-055).
pub const TAG: &str = "[ED]";

/// O corpo do `POST /dispatch`. Campo desconhecido é ignorado, como no
/// `Codable` do Swift.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DispatchRequest {
    pub target: String,
    /// `task` | `raw`; ausente é `raw`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    /// Sobrepõe o modo do perfil: `bracketed-paste` ou `plain` — shell e TUI de
    /// agente reagem diferente ao mesmo texto.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub inject: Option<String>,
    /// Imagens anexadas, em caminho absoluto. Cada uma é colada sozinha antes
    /// do texto: o Claude Code só troca caminho por anexo quando o paste é SÓ
    /// o caminho.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub images: Option<Vec<String>>,
    /// Quem mandou, quando é outro terminal. O Dispatcher preenche a partir do
    /// kernel, nunca do corpo.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub from: Option<String>,
}

impl DispatchRequest {
    pub fn new(target: impl Into<String>) -> Self {
        Self {
            target: target.into(),
            ..Self::default()
        }
    }

    /// O `POST /message?target=…`: o corpo é o texto puro, sem JSON — quem
    /// chama é um agente escrevendo por heredoc, e escapar aspas à mão é onde
    /// ele erra.
    pub fn from_message(target: impl Into<String>, body: &[u8]) -> Self {
        Self {
            text: Some(String::from_utf8_lossy(body).trim().to_owned()),
            ..Self::new(target)
        }
    }

    /// Sem cabeçalho explícito o agente confunde o pedido com conteúdo a
    /// escrever. Não há rodapé de "isso não autoriza nada" (ADR-038).
    fn agent_envelope(sender: &str, text: &str) -> String {
        format!("{TAG} mensagem de {sender}\n\n{text}")
    }

    /// Comando do CLI (`/clear`, `/model sonnet`): a primeira palavra é
    /// `/nome`, sem outra barra — `/Users/x/a.md` é caminho, não comando.
    pub fn is_slash_command(&self) -> bool {
        let Some(rest) = self.text.as_deref().and_then(|t| t.strip_prefix('/')) else {
            return false;
        };
        let name: String = rest.chars().take_while(|c| !c.is_whitespace()).collect();
        !name.is_empty()
            && !name.contains('/')
            && name.chars().next().is_some_and(char::is_alphabetic)
    }

    /// O que chega de uma mensagem entre terminais: envelope para agente, cru
    /// para shell — que executaria o cabeçalho como comando (ADR-066). Comando
    /// com `/` também vai cru: o CLI só o reconhece no começo do prompt.
    pub fn message(&self, sender: &str, to_shell: bool) -> Option<String> {
        let mut copy = self.clone();
        let raw = to_shell || self.is_slash_command();
        copy.from = if raw { None } else { Some(sender.to_owned()) };
        if raw {
            copy.kind = Some("raw".to_owned());
        }
        copy.build_prompt()
    }

    /// O aviso que vai antes do comando cru: sem ele o agente vê a conversa
    /// mudar sem saber quem mexeu.
    pub fn command_notice(&self, sender: &str) -> Option<String> {
        if !self.is_slash_command() {
            return None;
        }
        let text = self.text.as_deref()?;
        let command = text.split('\n').find(|l| !l.is_empty()).unwrap_or(text);
        Some(Self::agent_envelope(
            sender,
            &format!(
                "Aviso: logo depois desta mensagem chega o comando `{command}` no seu terminal, \
                 mandado por {sender}. Não precisa responder — só encerre o turno."
            ),
        ))
    }

    pub fn build_prompt(&self) -> Option<String> {
        let text = self.text.as_deref().filter(|t| !t.is_empty());
        if let Some(from) = self.from.as_deref().filter(|f| !f.is_empty()) {
            return text.map(|t| Self::agent_envelope(from, t));
        }
        match self.kind.as_deref().unwrap_or("raw") {
            "task" => {
                let text = text?;
                let mut out = TAG.to_owned();
                if let Some(file) = &self.file {
                    out.push(' ');
                    out.push_str(file);
                }
                Some(format!("{out}\n\n{text}\n\nAplique no código."))
            }
            _ => text.map(str::to_owned),
        }
    }
}

/// Mensagens de `sender` esperando leitura, pela cadeia de cada uma: o
/// remetente é o penúltimo elo (o último é o próprio destino). ADR-077.
pub fn sender_backlog<'a>(sender: &str, chains: impl IntoIterator<Item = &'a [String]>) -> usize {
    chains
        .into_iter()
        .filter(|chain| chain.len() >= 2 && chain[chain.len() - 2] == sender)
        .count()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(json: &str) -> DispatchRequest {
        serde_json::from_str(json).unwrap()
    }

    #[test]
    fn raw_is_the_text_itself() {
        let req = request(r#"{"target":"ws/t1","kind":"raw","text":"oi"}"#);
        assert_eq!(req.build_prompt().as_deref(), Some("oi"));
    }

    #[test]
    fn raw_without_text_is_nothing() {
        assert_eq!(
            request(r#"{"target":"ws/t1","kind":"raw"}"#).build_prompt(),
            None
        );
        assert_eq!(
            request(r#"{"target":"ws/t1","kind":"raw","text":""}"#).build_prompt(),
            None
        );
    }

    #[test]
    fn task_wraps_with_header_and_apply() {
        let req = request(r#"{"target":"ws/t1","kind":"task","file":"a.swift","text":"troque X"}"#);
        assert_eq!(
            req.build_prompt().as_deref(),
            Some("[ED] a.swift\n\ntroque X\n\nAplique no código.")
        );
    }

    #[test]
    fn removed_review_kind_delivers_nothing() {
        let req = request(
            r#"{"target":"ws/t1","kind":"review","file":"doc.md","comments":[{"body":"x"}]}"#,
        );
        assert_eq!(req.build_prompt(), None);
    }

    #[test]
    fn sender_turns_any_kind_into_the_agent_envelope() {
        let req =
            request(r#"{"target":"ws/t1","kind":"task","from":"deck/claude-2","text":"revise"}"#);
        let prompt = req.build_prompt().unwrap();
        assert_eq!(prompt, "[ED] mensagem de deck/claude-2\n\nrevise");
        assert!(!prompt.contains("autoriza"));
    }

    #[test]
    fn envelope_without_text_is_nothing() {
        assert_eq!(
            request(r#"{"target":"ws/t1","from":"deck/claude-2"}"#).build_prompt(),
            None
        );
    }

    #[test]
    fn missing_kind_defaults_to_raw() {
        let req = request(r#"{"target":"ws/t1","text":"corpo puro"}"#);
        assert_eq!(req.build_prompt().as_deref(), Some("corpo puro"));
    }

    #[test]
    fn message_to_shell_is_raw_and_to_agent_is_enveloped() {
        let mut req = DispatchRequest::new("deck/dev");
        req.text = Some("npm test".into());
        assert_eq!(
            req.message("deck/maestro", true).as_deref(),
            Some("npm test")
        );
        let enveloped = req.message("deck/maestro", false).unwrap_or_default();
        assert!(
            enveloped.starts_with("[ED] mensagem de deck/maestro"),
            "{enveloped}"
        );
        assert!(enveloped.ends_with("npm test"));
    }

    #[test]
    fn slash_command_goes_raw_with_notice_before() {
        let mut req = DispatchRequest::new("deck/dev");
        req.text = Some("/model sonnet".into());
        assert!(req.is_slash_command());
        assert_eq!(
            req.message("deck/maestro", false).as_deref(),
            Some("/model sonnet")
        );
        let notice = req.command_notice("deck/maestro").unwrap_or_default();
        assert!(notice.starts_with("[ED] mensagem de deck/maestro"));
        assert!(notice.contains("`/model sonnet`"));
    }

    #[test]
    fn path_or_text_is_not_a_command() {
        for text in [
            "/Users/x/a.md é o arquivo",
            "/ sozinho",
            "/2 itens",
            "oi /clear",
            "",
        ] {
            let mut req = DispatchRequest::new("deck/dev");
            req.text = Some(text.into());
            assert!(!req.is_slash_command(), "{text}");
            assert_eq!(req.command_notice("deck/maestro"), None, "{text}");
        }
        let mut compact = DispatchRequest::new("deck/dev");
        compact.text = Some("/compact foca no bug do login".into());
        assert!(compact.is_slash_command());
    }

    #[test]
    fn message_body_is_the_trimmed_text() {
        let req = DispatchRequest::from_message("deck/b", b"  oi\n\n");
        assert_eq!(req.target, "deck/b");
        assert_eq!(req.build_prompt().as_deref(), Some("oi"));
    }

    fn chains(raw: &[&[&str]]) -> Vec<Vec<String>> {
        raw.iter()
            .map(|c| c.iter().map(|s| (*s).to_owned()).collect())
            .collect()
    }

    #[test]
    fn backlog_counts_only_the_sender() {
        let chains = chains(&[
            &["deck/w01", "deck/maestro"],
            &["deck/w02", "deck/maestro"],
            &["deck/maestro", "deck/w01", "deck/maestro"],
            &["deck/w03", "deck/maestro"],
        ]);
        let count = |s| sender_backlog(s, chains.iter().map(Vec::as_slice));
        assert_eq!(count("deck/w01"), 2);
        assert_eq!(count("deck/w02"), 1);
        assert_eq!(count("deck/w09"), 0);
    }

    #[test]
    fn backlog_whole_team_counts_one_each() {
        let team: Vec<Vec<String>> = (1..=14)
            .map(|i| vec![format!("deck/w{i}"), "deck/maestro".to_owned()])
            .collect();
        assert!((1..=14).all(|i| {
            sender_backlog(&format!("deck/w{i}"), team.iter().map(Vec::as_slice)) == 1
        }));
    }
}
