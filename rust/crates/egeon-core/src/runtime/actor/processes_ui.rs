//! A janela "Processos" no `/ui` (decisão 37): a lista, encerrar órfãos e
//! encerrar os selecionados, com o ensaio que devolve a confirmação pronta.
//! A leitura e o SIGTERM são do `cli` (`processes_panel`), fora do ator.

use std::collections::HashSet;

use super::processes_commands::Panel;
use super::{Actor, ClientId};
use crate::features::processes::view::confirm;
use crate::protocol::message::{CommandKind, Reply};

impl Actor {
    /// `None`: a resposta sai quando a leitura terminar.
    pub(super) fn processes_ui(
        &mut self,
        client: ClientId,
        re: u64,
        kind: CommandKind,
    ) -> Option<Reply> {
        // `Some(pids)` em `ask`: só montar a confirmação, sem encerrar.
        let (action, ask): (Panel, Option<Option<HashSet<u32>>>) = match kind {
            CommandKind::Processes => (Panel::List, None),
            CommandKind::ProcessesReap(r) if r.dry_run => (Panel::List, Some(None)),
            CommandKind::ProcessesReap(_) => (Panel::KillOrphans, None),
            CommandKind::ProcessesKill(k) => {
                let pids: HashSet<u32> = k.pids.into_iter().collect();
                if k.dry_run {
                    (Panel::List, Some(Some(pids)))
                } else {
                    (Panel::Kill(pids), None)
                }
            }
            other => {
                return Some(Reply::err(
                    re,
                    format!("{} não é da janela de processos", other.name()),
                ));
            }
        };
        self.processes_panel(action, move |actor, result| {
            let reply = match result {
                // A leitura que não termina é erro, e não "0 no app".
                Err(error) => Reply::err(re, error),
                Ok(view) => match ask {
                    Some(pids) => Reply::with(re, &confirm(&view, pids.as_ref())),
                    None => Reply::with(re, &view),
                },
            };
            actor.send_reply(client, &reply);
        });
        None
    }
}
