//! A atividade de cada bancada na árvore: o `workspaces` carrega o resumo
//! (trabalhando, esperando você, terminou) que a barra lateral e o trilho
//! mostram, mas o resumo muda pelos ganchos dos agentes, sem passar por
//! nenhuma ação sobre a organização. O relógio compara com o último que foi
//! à tela e republica só quando mudou.

use std::collections::BTreeMap;

use super::Actor;
use crate::features::activity::model::ActivitySummary;

#[derive(Default)]
pub(super) struct ActivityWatch {
    /// O resumo da última árvore publicada, por bancada.
    pub(super) published: BTreeMap<String, ActivitySummary>,
}

impl Actor {
    pub(super) fn activity_tick(&mut self) {
        let now = self.dispatch.coordination.dispatcher.activity_summary();
        if now == self.activity_watch.published {
            return;
        }
        self.activity_watch.published = now;
        self.publish_org();
    }
}
