//! As pastas que a árvore mostra como existentes, relidas fora do ator: o
//! `publish_org` monta a árvore inteira e não pode perguntar ao disco.

use std::collections::HashMap;
use std::time::{Duration, SystemTime};

use super::{Actor, Msg};
use crate::runtime::org::{probe_access, probe_paths};

/// O Swift pergunta ao disco ao desenhar; aqui a pasta apagada aparece em
/// até este tempo.
const EXISTS_EVERY: Duration = Duration::from_secs(2);

#[derive(Default)]
pub(super) struct ExistsState {
    last: Option<SystemTime>,
    probing: bool,
}

impl Actor {
    pub(super) fn exists_tick(&mut self, now: SystemTime) {
        let due = self
            .exists
            .last
            .is_none_or(|last| now.duration_since(last).unwrap_or_default() >= EXISTS_EVERY);
        if self.exists.probing || !due {
            return;
        }
        self.exists.probing = true;
        self.exists.last = Some(now);
        let paths = self.org.watched_paths();
        let benches = self.org.bench_paths();
        let home = self.org.home.clone();
        let inbox = self.inbox.clone();
        tokio::spawn(async move {
            let fresh = tokio::task::spawn_blocking(move || {
                (probe_paths(paths), probe_access(benches, &home))
            })
            .await;
            let job = move |actor: &mut Actor| {
                actor.exists.probing = false;
                let Ok((fresh, denied)) = fresh else { return };
                let unlocked = actor.access_changed(denied);
                // Pasta nova no cache que existe não muda a tela: pasta não
                // lida já contava como existente.
                let old = &actor.org.existing;
                let changed = fresh
                    .iter()
                    .any(|(path, there)| old.get(path).copied().unwrap_or(true) != *there)
                    || old
                        .iter()
                        .any(|(path, there)| !there && !fresh.contains_key(path));
                actor.org.existing = fresh;
                if changed || unlocked {
                    actor.publish_org();
                }
            };
            let _ = inbox.send(Msg::Run(Box::new(job))).await;
        });
    }

    /// Guarda a recusa nova. A bancada viva que voltou a ter acesso reergue
    /// todos os agentes, vivos ou não, como o `restartAgents` do Swift ao
    /// destravar (main.swift:893, :3411): um agente que subiu com a pasta
    /// negada está de pé fora dela. Shell não lê regra e fica quieto.
    /// Devolve se a cortina mudou.
    pub(super) fn access_changed(&mut self, denied: HashMap<String, Option<String>>) -> bool {
        if denied == self.org.denied {
            return false;
        }
        let freed: Vec<String> = self
            .org
            .state
            .workbenches
            .iter()
            .filter(|b| {
                let path = b.url_path(&self.org.home);
                self.org.denied.contains_key(&path) && !denied.contains_key(&path)
            })
            .map(|b| b.id.clone())
            .filter(|id| self.org.live.contains(id))
            .collect();
        self.org.denied = denied;
        for id in freed {
            crate::log!("acesso: a bancada {id} voltou a ler a pasta; agentes de novo");
            self.restart_agents(&id);
        }
        true
    }

    fn restart_agents(&mut self, id: &str) {
        let Some(bench) = self
            .org
            .state
            .workbenches
            .iter()
            .find(|w| w.id == id)
            .cloned()
        else {
            return;
        };
        let agents = bench
            .nodes
            .iter()
            .filter(|n| n.kind == crate::features::node::model::NodeKind::Agent);
        for node in agents {
            if let Some(terminal) = crate::runtime::org::screen_id(&bench.id, &node.id)
                && self.nodes.contains_key(&terminal)
                && let Err(error) = self.close(&terminal)
            {
                crate::log!("acesso: {} não fechou — {error}", bench.address_of(node));
            }
            self.open_terminal(&bench, node);
        }
    }
}
