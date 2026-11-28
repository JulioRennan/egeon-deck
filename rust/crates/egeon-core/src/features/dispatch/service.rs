//! O Dispatcher: os alvos endereçáveis, a entrega com as guardas de cadeia e o
//! laço de 0,25s que drena filas e recalcula estados. Porte da classe
//! `Dispatcher` do `Dispatcher.swift`.
//!
//! Puro como o [`Target`]: quem chama passa o instante, a [`Surface`] (tela,
//! foco, processo) e a [`Topology`] (arestas da bancada), e executa os
//! [`Effect`] que voltam.

use std::collections::BTreeMap;
use std::time::SystemTime;

use thiserror::Error;

use super::profile::TargetProfile;
use super::request::{DispatchRequest, sender_backlog};
use super::stop::PeerWait;
use super::target::{Effect, Hook, Out, Surface, Target};
use crate::features::activity::model::ActivitySummary;
use crate::features::edge::model::EdgeConfig;
use crate::log;

/// Quanto o laço do Swift espera entre um `tick` e outro.
pub const TICK: std::time::Duration = std::time::Duration::from_millis(250);

/// As arestas e os papéis, que moram no modelo da bancada.
pub trait Topology {
    /// As arestas da bancada `workbench`, por id de nó.
    fn edges(&self, workbench: &str) -> Vec<EdgeConfig>;
    /// O papel do nó, para o `egeon peers`.
    fn role(&self, _address: &str) -> Option<String> {
        None
    }
}

/// Um vizinho que este terminal pode acionar.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Peer {
    pub address: String,
    pub cli: String,
    pub role: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum DispatchError {
    #[error("alvo desconhecido '{target}'. disponíveis: {}", available.join(", "))]
    UnknownTarget {
        target: String,
        available: Vec<String>,
    },
    #[error("requisição não produziu prompt (text vazio?)")]
    EmptyPrompt,
    #[error("não existe ligação de {from} para {to} — desenhe a aresta no canvas")]
    NotLinked { from: String, to: String },
    #[error(
        "cadeia recusada: a ligação {from} → {to} já disparou {limit}× nesta conversa ({}). Volte a falar com o usuário.",
        chain.join(" → ")
    )]
    TooManySends {
        from: String,
        to: String,
        limit: i64,
        chain: Vec<String>,
    },
    #[error(
        "cadeia recusada: {target} ainda tem {pending} mensagens suas por ler (limite {limit}). Espere ele responder antes de mandar outra."
    )]
    TargetBacklogged {
        target: String,
        pending: usize,
        limit: i64,
    },
}

/// A bancada do endereço: o que vem antes da primeira barra.
pub fn workbench_of(address: &str) -> &str {
    address.split('/').find(|s| !s.is_empty()).unwrap_or("")
}

/// O id do nó: o que vem depois da última barra.
pub fn node_of(address: &str) -> &str {
    address.rsplit('/').find(|s| !s.is_empty()).unwrap_or("")
}

#[derive(Default)]
pub struct Dispatcher {
    targets: BTreeMap<String, Target>,
}

impl Dispatcher {
    pub fn new() -> Self {
        Self::default()
    }

    /// `hooked`: o terminal foi lançado com os nossos ganchos — quem monta a
    /// linha de comando sabe, e descobrir no primeiro relato custava uma
    /// janela em que a tela mandava (ADR-024).
    pub fn register(
        &mut self,
        address: impl Into<String>,
        profile: Option<TargetProfile>,
        hooked: bool,
        now: SystemTime,
    ) {
        let address = address.into();
        let target = Target::new(address.clone(), profile, hooked, now);
        log!(
            "dispatcher: alvo registrado {address} ({})",
            target.display_name()
        );
        self.targets.insert(address, target);
    }

    pub fn unregister(&mut self, address: &str, now: SystemTime) -> Vec<Effect> {
        self.targets.remove(address);
        let mut out = Out::default();
        out.effects.push(Effect::DropPermissions {
            address: address.to_owned(),
            why: "terminal saiu",
        });
        out.settled.push(address.to_owned());
        self.spread(out, now)
    }

    /// Quem encerrou sem mandar de volta libera quem esperava por ele
    /// (ADR-067). Em laço porque liberar um pode encerrar outro.
    fn spread(&mut self, mut out: Out, now: SystemTime) -> Vec<Effect> {
        let mut next = 0;
        while next < out.settled.len() {
            let settled = out.settled[next].clone();
            next += 1;
            for target in self.targets.values_mut() {
                if target.address != settled {
                    target.peer_settled(&settled, now, &mut out);
                }
            }
        }
        out.effects
    }

    /// Troca o endereço de um alvo vivo, sem derrubar o pty. `false` quando não
    /// havia o que trocar. A mesa de permissões é renomeada por quem chama.
    pub fn rekey(&mut self, old: &str, new: &str) -> bool {
        if old == new {
            return false;
        }
        let Some(mut target) = self.targets.remove(old) else {
            return false;
        };
        new.clone_into(&mut target.address);
        self.targets.insert(new.to_owned(), target);
        for other in self.targets.values_mut() {
            other.awaiting_peers.renamed(old, new);
            other.owed_replies.renamed(old, new);
        }
        log!("dispatcher: alvo {old} → {new}");
        true
    }

    pub fn addresses(&self) -> Vec<String> {
        self.targets.keys().cloned().collect()
    }

    /// Endereços de pé: o morto continua registrado (o card está na tela), mas
    /// oferecê-lo como destino é oferecer um buraco.
    pub fn active_addresses(&self) -> Vec<String> {
        self.targets
            .iter()
            .filter(|(_, t)| *t.activity() != crate::features::activity::model::Activity::Dead)
            .map(|(a, _)| a.clone())
            .collect()
    }

    pub fn target(&self, address: &str) -> Option<&Target> {
        self.targets.get(address)
    }

    /// Você abriu esta bancada: só o verde dos terminais dela cai.
    pub fn workbench_opened(&mut self, name: &str) {
        let prefix = format!("{name}/");
        for (address, target) in &mut self.targets {
            if address.starts_with(&prefix) {
                target.mark_done_seen();
            }
        }
    }

    /// Resolve um id de nó para endereço completo dentro da mesma bancada:
    /// escrever só o id é o erro natural do agente.
    pub fn resolve(&self, name: &str, sibling_of: &str) -> Option<String> {
        if self.targets.contains_key(name) {
            return Some(name.to_owned());
        }
        let qualified = format!("{}/{name}", workbench_of(sibling_of));
        self.targets.contains_key(&qualified).then_some(qualified)
    }

    /// Entrega um pedido. `origin` é o terminal de onde a conexão partiu,
    /// resolvido pelo kernel — `None` é você, que entrega sem guardas. Vem de
    /// fora e não do pedido: no corpo, o agente escreveria o que quisesse.
    pub fn dispatch(
        &mut self,
        request: &DispatchRequest,
        origin: Option<&str>,
        topology: &dyn Topology,
    ) -> Result<String, DispatchError> {
        let address = origin
            .and_then(|o| self.resolve(&request.target, o))
            .unwrap_or_else(|| request.target.clone());
        if !self.targets.contains_key(&address) {
            return Err(DispatchError::UnknownTarget {
                target: request.target.clone(),
                available: self.addresses(),
            });
        }

        let Some(sender) = origin.filter(|o| self.targets.contains_key(*o)) else {
            let images = request.images.clone().unwrap_or_default();
            let prompt = request
                .build_prompt()
                .or_else(|| (!images.is_empty()).then(String::new))
                .ok_or(DispatchError::EmptyPrompt)?;
            let destination = self.target_mut(&address)?;
            destination.enqueue(prompt, request.inject.clone(), Vec::new(), false, images);
            return Ok(format!(
                "enfileirado para {address}; {} na fila",
                destination.pending()
            ));
        };
        let sender = sender.to_owned();

        let (to_shell, mine, awaiting) = {
            let destination = self.target_mut(&address)?;
            (
                destination.profile().is_none(),
                sender_backlog(&sender, destination.queued_chains()),
                destination.awaiting_peers.clone(),
            )
        };
        // Shell recebe o texto cru: o cabeçalho viraria comando no zsh
        // (ADR-066).
        let prompt = request
            .message(&sender, to_shell)
            .ok_or(DispatchError::EmptyPrompt)?;
        let edge = link(topology, &sender, &address).ok_or_else(|| DispatchError::NotLinked {
            from: sender.clone(),
            to: address.clone(),
        })?;

        // A cadeia só avança na ENTREGA: quem dispara em laço manda tudo antes
        // de o destino ler a primeira, e a profundidade nem é consultada. Por
        // remetente e com o número da ligação (ADR-077).
        if let Some(limit) = edge.max_sends
            && i64::try_from(mine).unwrap_or(i64::MAX) >= limit.max(1)
        {
            log!(
                "cadeia[{sender} → {address}]: RECUSADA, {mine} mensagens dele ainda por ler (limite {limit})"
            );
            return Err(DispatchError::TargetBacklogged {
                target: address,
                pending: mine,
                limit,
            });
        }

        let (mut chain, owed) = {
            let origin = self.target_mut(&sender)?;
            let chain = if origin.chain.is_empty() {
                vec![sender.clone()]
            } else {
                origin.chain.clone()
            };
            (chain, origin.owed_replies.clone())
        };
        chain.push(address.clone());

        // O limite da seta é o único: "este par pode conversar N vezes" nesta
        // cadeia (ADR-077).
        let sends = send_count(&sender, &address, &chain);
        if let Some(allowed) = edge.max_sends
            && i64::try_from(sends).unwrap_or(i64::MAX) > allowed
        {
            log!(
                "cadeia[{sender} → {address}]: RECUSADA, {sends}º envio nesta ligação (limite {allowed}) — {}",
                chain.join(" → ")
            );
            return Err(DispatchError::TooManySends {
                from: sender,
                to: address,
                limit: allowed,
                chain,
            });
        }

        let is_reply = PeerWait::is_reply(&awaiting, &owed, &sender, &address);
        let handoff = !to_shell && !request.is_slash_command();
        {
            let destination = self.target_mut(&address)?;
            if !to_shell && let Some(notice) = request.command_notice(&sender) {
                destination.enqueue(
                    notice,
                    request.inject.clone(),
                    chain.clone(),
                    true,
                    Vec::new(),
                );
            }
            destination.enqueue(
                prompt,
                request.inject.clone(),
                chain.clone(),
                false,
                Vec::new(),
            );
        }
        // Passou o bastão: o fim de turno DELE não te chama mais. Para shell
        // não há bastão; resposta não abre espera (ADR-058); comando também
        // não — `/clear` não tem resposta.
        if handoff {
            let origin = self.target_mut(&sender)?;
            origin.handed_off = true;
            if is_reply {
                origin.owed_replies.resolved(&address);
            } else {
                origin.awaiting_peers.sent(&address);
                self.target_mut(&address)?.owed_replies.sent(&sender);
            }
        }
        self.target_mut(&address)?.peer_answered(&sender);
        let budget = format!(
            "envio {sends}/{}",
            edge.max_sends.map_or("∞".to_owned(), |m| m.to_string())
        );
        log!(
            "cadeia[{sender} → {address}]: {budget} — {}",
            chain.join(" → ")
        );
        let pending = self.targets.get(&address).map_or(0, Target::pending);
        Ok(format!(
            "enfileirado para {address}; {pending} na fila; {budget}"
        ))
    }

    fn target_mut(&mut self, address: &str) -> Result<&mut Target, DispatchError> {
        let available = self.addresses();
        self.targets
            .get_mut(address)
            .ok_or_else(|| DispatchError::UnknownTarget {
                target: address.to_owned(),
                available,
            })
    }

    /// Um texto do app na fila deste terminal, fora de cadeia — o aviso de
    /// permissão ao maestro. `false` quando o alvo não existe.
    pub fn enqueue(&mut self, address: &str, prompt: String) -> bool {
        let Some(target) = self.targets.get_mut(address) else {
            return false;
        };
        target.enqueue(prompt, None, Vec::new(), false, Vec::new());
        true
    }

    /// Quem este terminal pode acionar agora — perguntado na hora, porque o
    /// catálogo do arranque congelava a topologia.
    pub fn peers(&self, address: &str, topology: &dyn Topology) -> Vec<Peer> {
        let workbench = workbench_of(address);
        let id = node_of(address);
        topology
            .edges(workbench)
            .into_iter()
            .filter(|edge| edge.from == id)
            .filter_map(|edge| {
                let peer = format!("{workbench}/{}", edge.to);
                let target = self.targets.get(&peer)?;
                Some(Peer {
                    cli: target.display_name().to_owned(),
                    role: topology.role(&peer),
                    address: peer,
                })
            })
            .collect()
    }

    /// Ler a tela de outro terminal: de fora vale para qualquer alvo; de
    /// dentro, só para quem ele já pode acionar (ADR-012).
    pub fn may_peek(address: &str, from: Option<&str>, peers: &[String]) -> bool {
        match from {
            None => true,
            Some(origin) => address == origin || peers.iter().any(|p| p == address),
        }
    }

    /// Quanto cada bancada tem de trabalho e de espera por você — inclusive as
    /// que não estão na tela.
    pub fn activity_summary(&self) -> BTreeMap<String, ActivitySummary> {
        let mut out: BTreeMap<String, ActivitySummary> = BTreeMap::new();
        for (address, target) in &self.targets {
            out.entry(workbench_of(address).to_owned())
                .or_default()
                .count(target.activity());
        }
        out
    }

    /// Saíram bytes do pty deste terminal (a tela já os recebeu).
    pub fn output(&mut self, address: &str, now: SystemTime, surface: &dyn Surface) {
        if let Some(target) = self.targets.get_mut(address) {
            target.output(now, surface);
        }
    }

    /// Você digitou dentro deste terminal — não a injeção, que não passa por
    /// aqui. Atalho do app (⌘ fora o colar) não conta.
    pub fn user_typed(&mut self, address: &str, now: SystemTime) -> Vec<Effect> {
        let mut out = Out::default();
        if let Some(target) = self.targets.get_mut(address) {
            target.user_typed(&mut out);
        }
        self.spread(out, now)
    }

    pub fn permission_answered(&mut self, address: &str, now: SystemTime) -> Vec<Effect> {
        let mut out = Out::default();
        if let Some(target) = self.targets.get_mut(address) {
            target.permission_answered(&mut out);
        }
        self.spread(out, now)
    }

    /// O gancho do CLI relatou (`/activity`, `/conversation`). `None` quando o
    /// endereço não é de alvo nenhum.
    pub fn hook_reported(
        &mut self,
        address: &str,
        hook: Hook,
        now: SystemTime,
        surface: &dyn Surface,
    ) -> Option<Vec<Effect>> {
        let mut out = Out::default();
        let target = self.targets.get_mut(address)?;
        target.hook_reported(hook, now, surface, &mut out);
        Some(self.spread(out, now))
    }

    /// `/retry`: tentar agora ou desistir da tentativa agendada. `None` quando
    /// não há tentativa agendada nesse alvo.
    pub fn retry_control(
        &mut self,
        address: &str,
        now_flag: bool,
        now: SystemTime,
    ) -> Option<Vec<Effect>> {
        let mut out = Out::default();
        let target = self.targets.get_mut(address)?;
        if !target.retry_control(now_flag, &mut out) {
            return None;
        }
        Some(self.spread(out, now))
    }

    /// O prazo guardado mais próximo de todos os alvos: o ator chama `tick`
    /// nele, além do laço de 0,25s.
    pub fn next_deadline(&self) -> Option<SystemTime> {
        self.targets
            .values()
            .filter_map(Target::next_deadline)
            .min()
    }

    /// O laço: prazos vencidos, entrega e estado, nessa ordem — ler o estado
    /// antes de entregar deixaria a UI um tique atrás.
    pub fn tick(&mut self, now: SystemTime, surface: &dyn Surface) -> Vec<Effect> {
        let mut out = Out::default();
        for target in self.targets.values_mut() {
            target.fire_due(now, surface, &mut out);
            target.drain(now, &mut out);
            target.update_activity(now, surface, &mut out);
        }
        self.spread(out, now)
    }
}

fn link(topology: &dyn Topology, from: &str, to: &str) -> Option<EdgeConfig> {
    let (from_id, to_id) = (node_of(from), node_of(to));
    topology
        .edges(workbench_of(from))
        .into_iter()
        .find(|e| e.from == from_id && e.to == to_id)
}

/// Quantas vezes esta seta já disparou nesta cadeia, contando a de agora: um
/// `from` seguido de um `to`.
fn send_count(from: &str, to: &str, chain: &[String]) -> usize {
    chain
        .windows(2)
        .filter(|pair| pair[0] == from && pair[1] == to)
        .count()
}
