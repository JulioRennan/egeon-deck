//! Como um turno fechou: o que o gancho `Stop` conta, a decisão do fim e a
//! espera por vizinhos. Porte de `StopReport.swift`.

use std::collections::HashMap;

use super::marker::Marker;

/// O que o `Stop` conta do turno que acabou, além do instante (ADR-067).
/// Os campos opcionais são `None` quando o CLI não relatou — aí decide o
/// marcador, como antes.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct StopReport {
    /// Tarefas de fundo mais crons que ainda vão acordar o agente.
    pub background: Option<u32>,
    /// Vigias de página publicada, fora do `background` (ADR-081): vivem a
    /// sessão inteira e, contados, deixavam o card na ampulheta para sempre.
    pub watchers: u32,
    /// O fim da última mensagem do agente.
    pub last_message: Option<String>,
    /// O que é cada tarefa de fundo, só para o log.
    pub tasks: Vec<String>,
}

impl StopReport {
    /// Lido da query de `/activity`: `bg`, `bgw` (vigias, contidos em `bg`),
    /// `bgd` (descrições separadas por ` | `) e `last`.
    pub fn from_query(query: &HashMap<String, String>) -> Self {
        let watchers = query
            .get("bgw")
            .and_then(|v| v.parse::<i64>().ok())
            .unwrap_or(0);
        let background = query
            .get("bg")
            .and_then(|v| v.parse::<i64>().ok())
            .map(|bg| (bg - watchers).max(0));
        Self {
            background: background.and_then(|b| u32::try_from(b).ok()),
            watchers: u32::try_from(watchers.max(0)).unwrap_or(0),
            last_message: query.get("last").filter(|l| !l.is_empty()).cloned(),
            tasks: query
                .get("bgd")
                .map(|d| {
                    d.split(" | ")
                        .filter(|t| !t.is_empty())
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StopOutcome {
    Finished,
    Asked,
    Background,
    /// Acionou um vizinho que ainda não respondeu.
    Awaiting,
}

impl StopOutcome {
    /// A ordem é o que importa: vizinho pendente vence tudo, inclusive
    /// `[[ED:ask]]`; a pergunta vence a ampulheta; `[[ED:ok]]` vence a contagem
    /// de fundo; o payload vence o marcador no resto.
    pub fn decide(marker: Option<Marker>, background: Option<u32>, awaiting_peers: bool) -> Self {
        if awaiting_peers {
            return Self::Awaiting;
        }
        match marker {
            Some(Marker::Ask) => return Self::Asked,
            Some(Marker::Ok) => return Self::Finished,
            _ => {}
        }
        if let Some(background) = background {
            return if background > 0 {
                Self::Background
            } else {
                Self::Finished
            };
        }
        match marker {
            Some(Marker::Wait) => Self::Background,
            _ => Self::Finished,
        }
    }
}

/// Os vizinhos acionados que ainda não responderam. Sai quem responde e quem
/// encerra o turno sem responder.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PeerWait {
    peers: Vec<String>,
}

impl PeerWait {
    pub fn peers(&self) -> &[String] {
        &self.peers
    }

    pub fn is_empty(&self) -> bool {
        self.peers.is_empty()
    }

    pub fn contains(&self, address: &str) -> bool {
        self.peers.iter().any(|p| p == address)
    }

    pub fn sent(&mut self, address: &str) {
        if !self.contains(address) {
            self.peers.push(address.to_owned());
        }
    }

    /// `true` quando o endereço estava na lista.
    pub fn resolved(&mut self, address: &str) -> bool {
        let Some(index) = self.peers.iter().position(|p| p == address) else {
            return false;
        };
        self.peers.remove(index);
        true
    }

    pub fn clear(&mut self) {
        self.peers.clear();
    }

    /// A bancada mudou de nome: o endereço do vizinho mudou junto.
    pub fn renamed(&mut self, old: &str, new: &str) {
        for peer in &mut self.peers {
            if peer == old {
                new.clone_into(peer);
            }
        }
    }

    /// Esta mensagem de `sender` para `destination` é a volta de um pedido
    /// (ADR-058)? Dois lados, porque a espera de quem pediu é zerada quando
    /// VOCÊ fala com ele no meio, e a dívida de quem recebeu não.
    pub fn is_reply(awaiting: &PeerWait, owed: &PeerWait, sender: &str, destination: &str) -> bool {
        awaiting.contains(sender) || owed.contains(destination)
    }

    /// Os nomes sem a bancada — no card todos são da mesma.
    pub fn names(&self) -> Vec<String> {
        self.peers
            .iter()
            .map(|p| {
                p.rsplit('/')
                    .find(|s| !s.is_empty())
                    .unwrap_or(p)
                    .to_owned()
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn q(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| ((*k).to_owned(), (*v).to_owned()))
            .collect()
    }

    use Marker::{Ask, Ok, Wait};
    use StopOutcome as O;

    #[test]
    fn query_carries_background_and_last_message() {
        let report = StopReport::from_query(&q(&[("bg", "2"), ("last", "feito\n[[ED:ok]]")]));
        assert_eq!(report.background, Some(2));
        assert_eq!(report.last_message.as_deref(), Some("feito\n[[ED:ok]]"));
    }

    #[test]
    fn page_watchers_are_not_background_work() {
        let only = StopReport::from_query(&q(&[("bg", "1"), ("bgw", "1")]));
        assert_eq!(only.background, Some(0));
        assert_eq!(only.watchers, 1);
        assert_eq!(O::decide(Some(Ok), only.background, false), O::Finished);

        let shell = StopReport::from_query(&q(&[("bg", "26"), ("bgw", "25")]));
        assert_eq!(shell.background, Some(1));
        assert_eq!(O::decide(None, shell.background, false), O::Background);

        assert_eq!(
            StopReport::from_query(&q(&[("bg", "2")])).background,
            Some(2)
        );
        assert_eq!(
            StopReport::from_query(&q(&[("bg", "1"), ("bgw", "3")])).background,
            Some(0)
        );
    }

    #[test]
    fn query_without_fields_is_unknown() {
        let report = StopReport::from_query(&q(&[("transcript", "/tmp/x.jsonl"), ("last", "")]));
        assert_eq!(report.background, None);
        assert_eq!(report.last_message, None);
    }

    #[test]
    fn pending_peer_beats_ask() {
        assert_eq!(O::decide(Some(Ask), Some(0), true), O::Awaiting);
        assert_eq!(O::decide(Some(Ok), None, true), O::Awaiting);
        assert_eq!(O::decide(None, Some(3), true), O::Awaiting);
    }

    #[test]
    fn background_count_decides_wait_and_silence() {
        assert_eq!(O::decide(Some(Wait), Some(0), false), O::Finished);
        assert_eq!(O::decide(Some(Wait), Some(2), false), O::Background);
        assert_eq!(O::decide(None, Some(1), false), O::Background);
        assert_eq!(O::decide(None, Some(0), false), O::Finished);
        assert_eq!(O::decide(Some(Ask), Some(0), false), O::Asked);
    }

    #[test]
    fn ok_beats_long_lived_background() {
        assert_eq!(O::decide(Some(Ok), Some(1), false), O::Finished);
        assert_eq!(O::decide(Some(Ok), Some(5), false), O::Finished);
        assert_eq!(O::decide(Some(Ok), Some(1), true), O::Awaiting);
    }

    #[test]
    fn background_tasks_are_described_for_the_log() {
        let report = StopReport::from_query(&q(&[
            ("bg", "2"),
            ("bgd", "shell: python3 -m http.server | cron: /loop deploy"),
        ]));
        assert_eq!(
            report.tasks,
            ["shell: python3 -m http.server", "cron: /loop deploy"]
        );
        assert!(
            StopReport::from_query(&q(&[("bg", "0"), ("bgd", "")]))
                .tasks
                .is_empty()
        );
    }

    #[test]
    fn reply_is_recognized_from_either_side() {
        let mut asked = PeerWait::default();
        let mut owed = PeerWait::default();
        asked.sent("deck/b");
        owed.sent("deck/a");
        assert!(PeerWait::is_reply(&asked, &owed, "deck/b", "deck/a"));

        asked.clear();
        assert!(PeerWait::is_reply(&asked, &owed, "deck/b", "deck/a"));

        owed.resolved("deck/a");
        assert!(!PeerWait::is_reply(&asked, &owed, "deck/b", "deck/a"));
        assert!(!PeerWait::is_reply(
            &PeerWait::default(),
            &PeerWait::default(),
            "deck/b",
            "deck/c"
        ));
    }

    #[test]
    fn ask_beats_background() {
        assert_eq!(O::decide(Some(Ask), Some(1), false), O::Asked);
    }

    #[test]
    fn without_payload_the_marker_decides() {
        assert_eq!(O::decide(Some(Ask), None, false), O::Asked);
        assert_eq!(O::decide(Some(Wait), None, false), O::Background);
        assert_eq!(O::decide(Some(Ok), None, false), O::Finished);
        assert_eq!(O::decide(None, None, false), O::Finished);
    }

    #[test]
    fn peer_wait_keeps_order_and_no_duplicates() {
        let mut wait = PeerWait::default();
        wait.sent("deck/back");
        wait.sent("deck/front");
        wait.sent("deck/back");
        assert_eq!(wait.peers(), ["deck/back", "deck/front"]);
        assert_eq!(wait.names(), ["back", "front"]);
        wait.sent("deck/");
        assert_eq!(
            wait.names(),
            ["back", "front", "deck"],
            "como o split do Swift"
        );
    }

    #[test]
    fn peer_wait_resolves_only_who_is_there() {
        let mut wait = PeerWait::default();
        wait.sent("deck/back");
        assert!(!wait.resolved("deck/front"));
        assert!(wait.resolved("deck/back"));
        assert!(wait.is_empty());
    }

    #[test]
    fn peer_wait_follows_rename() {
        let mut wait = PeerWait::default();
        wait.sent("deck/back");
        wait.renamed("deck/back", "deck2/back");
        assert_eq!(wait.peers(), ["deck2/back"]);
    }
}
